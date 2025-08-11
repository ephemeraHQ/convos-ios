import Combine
import Foundation
import UIKit
import UserNotifications

enum PushNotificationError: Error {
    case noInstallations
    case noActiveSession
    case registrationFailed(String)
    case timeout
}

@Observable
class PushNotificationManager: NSObject {
    static let shared: PushNotificationManager = PushNotificationManager()

    var deviceToken: String?
    var isAuthorized: Bool = false
    var authorizationStatus: UNAuthorizationStatus = .notDetermined
    var registrationError: Error?

    private let notificationProcessor: NotificationProcessor
    private let convosClient: ConvosClient
    private var cancellables: Set<AnyCancellable> = .init()
    private var retryTask: Task<Void, Never>?
    private var retryAttempt: Int = 0

    private override init() {
        // Get app group identifier from ConfigManager
        let appGroupId = ConfigManager.shared.currentEnvironment.appGroupIdentifier
        self.notificationProcessor = NotificationProcessor(appGroupIdentifier: appGroupId)
        self.convosClient = ConvosClient.client(environment: ConfigManager.shared.currentEnvironment)

        super.init()

        Task {
            await checkAuthorizationStatus()
        }

        // Re-attempt registration when auth state becomes ready
        convosClient.authState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                switch state {
                case .authorized, .registered:
                    if let token = self.deviceToken {
                        Task { await self.updateDevicePushToken(token) }
                    }
                default:
                    break
                }
            }
            .store(in: &cancellables)

        // Also try when app comes to foreground
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard let token = self.deviceToken else { return }
                await self.updateDevicePushToken(token)
            }
        }
    }

    // MARK: - Authorization

    func checkAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
        isAuthorized = settings.authorizationStatus == .authorized
    }

    func requestAuthorization() async throws {
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])

        await checkAuthorizationStatus()

        if granted {
            await registerForRemoteNotifications()
        }
    }

    // MARK: - Registration

    private func registerForRemoteNotifications() async {
        await MainActor.run {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    // MARK: - Device Token Handling

    func handleDeviceToken(_ deviceToken: Data) {
        let tokenParts = deviceToken.map { data in String(format: "%02.2hhx", data) }
        let token = tokenParts.joined()

        Logger.info("✅ Received device token from APNS: \(token)")
        self.deviceToken = token

        // Store token in shared storage
        notificationProcessor.storeDeviceToken(token)
        Logger.info("✅ Stored device token in shared storage")

        Task {
            await updateDevicePushToken(token)
        }
    }

    // MARK: - Manual Registration (for debugging)

    func manuallyRegisterCurrentToken() async {
        Logger.info("Manual push token update requested")

        guard let currentToken = deviceToken else {
            Logger.error("❌ No device token available for manual update")
            return
        }

        Logger.info("Current device token: \(currentToken)")
        await updateDevicePushToken(currentToken)
    }

    func handleRegistrationError(_ error: Error) {
        Logger.error("❌ Failed to register for remote notifications: \(error)")
        self.registrationError = error
    }

    // MARK: - Device Update

    private func updateDevicePushToken(_ token: String) async {
        Logger.info("Updating device push token")

        do {
            guard isSessionReady() else {
                scheduleRetry(with: token)
                return
            }

            // Get current user and device info
            let userId = try await getCurrentUserId()
            let deviceId = await UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString

            // Since inboxReadyPublisher never emits (the original problem), we need to manually create
            // an authenticated API client using the stored JWT token that we know exists

            // Get the first available inbox to extract inbox ID for JWT lookup
            let allInboxes = try convosClient.session.inboxesRepository.allInboxes()
            guard let firstInbox = allInboxes.first else {
                Logger.error("❌ No inboxes found - cannot get inbox ID")
                throw PushNotificationError.noActiveSession
            }

            // Check if we have a stored JWT token for authentication
            let keychainService = KeychainService<ConvosJWTKeychainItem>()
            guard let storedJWT = try? keychainService.retrieveString(.init(inboxId: firstInbox.inboxId)),
                  !storedJWT.isEmpty else {
                Logger.error("No stored JWT token - cannot authenticate push token update")
                throw PushNotificationError.noActiveSession
            }

            // Create the API client directly using the environment
            _ = ConvosAPIClientFactory.client(environment: ConfigManager.shared.currentEnvironment)

            // First, check if the current push token is already set correctly
            let environment = ConfigManager.shared.currentEnvironment
            guard let apiBaseURL = URL(string: environment.apiBaseURL) else {
                Logger.error("Invalid API base URL")
                throw PushNotificationError.noActiveSession
            }

            // GET current device state
            let getUrl = apiBaseURL.appendingPathComponent("v1/devices/\(userId)/\(deviceId)")
            var getRequest = URLRequest(url: getUrl)
            getRequest.httpMethod = "GET"
            getRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            getRequest.setValue(storedJWT, forHTTPHeaderField: "X-Convos-AuthToken")

            do {
                let (getCurrentData, getCurrentResponse) = try await URLSession.shared.data(for: getRequest)

                if let getCurrentHttpResponse = getCurrentResponse as? HTTPURLResponse,
                   200...299 ~= getCurrentHttpResponse.statusCode,
                   !getCurrentData.isEmpty {
                    let currentDevice = try JSONDecoder().decode(ConvosAPI.DeviceUpdateResponse.self, from: getCurrentData)

                    let currentApnsEnv = environment.apnsEnvironment == .sandbox ? "sandbox" : "production"

                    // Check if token and environment match
                    if currentDevice.pushToken == token && currentDevice.apnsEnv == currentApnsEnv {
                        Logger.info("✅ Push token already up to date, skipping update")
                        registrationError = nil
                        retryAttempt = 0
                        retryTask?.cancel()
                        retryTask = nil
                        return
                    }
                }
            } catch {
                // Continue with update if we can't get current state
            }

            let url = apiBaseURL.appendingPathComponent("v1/devices/\(userId)/\(deviceId)")
            var request = URLRequest(url: url)
            request.httpMethod = "PATCH"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(storedJWT, forHTTPHeaderField: "X-Convos-AuthToken")

            let updateRequest = ConvosAPI.DeviceUpdateRequest(
                pushToken: token,
                pushTokenType: ConvosAPI.DeviceUpdateRequest.DeviceUpdatePushTokenType.apns,
                apnsEnv: environment.apnsEnvironment == .sandbox ?
                ConvosAPI.DeviceUpdateRequest.DeviceUpdateApnsEnvironment.sandbox :
                    ConvosAPI.DeviceUpdateRequest.DeviceUpdateApnsEnvironment.production
            )

            request.httpBody = try JSONEncoder().encode(updateRequest)

            let (data, httpResponse) = try await URLSession.shared.data(for: request)

            guard let httpResponse = httpResponse as? HTTPURLResponse else {
                Logger.error("Invalid HTTP response")
                throw PushNotificationError.registrationFailed("Invalid response")
            }

            guard 200...299 ~= httpResponse.statusCode else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                Logger.error("HTTP error \(httpResponse.statusCode): \(errorMessage)")
                throw PushNotificationError.registrationFailed("HTTP \(httpResponse.statusCode): \(errorMessage)")
            }

            // Try to decode response, but don't fail if it's empty or missing expected fields
            if !data.isEmpty {
                do {
                    let response = try JSONDecoder().decode(ConvosAPI.DeviceUpdateResponse.self, from: data)
                    Logger.info("✅ Successfully updated device push token: \(response)")
                } catch {
                    // Log the response body for debugging
                    let responseString = String(data: data, encoding: .utf8) ?? "Unable to decode response"
                    Logger.info("✅ Successfully updated device push token (response parsing failed): \(responseString)")
                    Logger.info("Response parsing error: \(error)")
                }
            } else {
                Logger.info("✅ Successfully updated device push token (empty response)")
            }
            registrationError = nil
            retryAttempt = 0
            retryTask?.cancel()
            retryTask = nil
        } catch {
            Logger.error("Failed to update device push token: \(error)")
            registrationError = error
            scheduleRetry(with: token)
        }
    }

    private func isSessionReady() -> Bool {
        do {
            let inboxes = try convosClient.session.inboxesRepository.allInboxes()
            return !inboxes.isEmpty
        } catch {
            return false
        }
    }

    private func scheduleRetry(with token: String) {
        // Exponential backoff up to 5 minutes
        let delaySeconds = min(pow(2.0, Double(retryAttempt)), 300.0)
        retryAttempt = min(retryAttempt + 1, 10)

        retryTask?.cancel()
        retryTask = Task { [weak self] in
            guard let self else { return }
            let ns = UInt64(delaySeconds * 1_000_000_000)
            try? await Task.sleep(nanoseconds: ns)
            await self.updateDevicePushToken(token)
        }
    }

    private func getCurrentUserId() async throws -> String {
        // Get the first available inbox to extract user ID
        let allInboxes = try convosClient.session.inboxesRepository.allInboxes()

        guard let firstInbox = allInboxes.first else {
            Logger.error("No inboxes found - cannot get user ID")
            throw PushNotificationError.noActiveSession
        }

        // Use the provider ID as the user ID (this is what we send to backend)
        return firstInbox.providerId
    }

    // MARK: - Topic Subscription (for future use)

    func subscribeToTopic(_ topic: String) async {
        Logger.debug("Subscribing to topic: \(topic)")
        notificationProcessor.addSubscribedTopic(topic)

        // @lourou: Notify backend about topic subscription
        // This should tell the backend to start sending notifications for this topic
    }

    func unsubscribeFromTopic(_ topic: String) async {
        Logger.debug("Unsubscribing from topic: \(topic)")
        notificationProcessor.removeSubscribedTopic(topic)

        // @lourou: Notify backend about topic unsubscription
        // This should tell the backend to stop sending notifications for this topic
    }

    func getSubscribedTopics() -> Set<String> {
        return notificationProcessor.getSubscribedTopics()
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension PushNotificationManager: UNUserNotificationCenterDelegate {
    // Handle notifications when app is in foreground
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        let userInfo = notification.request.content.userInfo
        Logger.debug("Received notification in foreground: \(userInfo)")

        // @lourou: Process the notification payload here if needed
        // You might want to decrypt XMTP messages or update local state

        // For now, we'll process the notification in the background
        Task { @MainActor in
            await self.processIncomingNotification(userInfo)
        }

        // Show notification even when app is in foreground
        return [.banner, .badge, .sound]
    }

    // Handle notification tap
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        Logger.debug("User tapped notification: \(userInfo)")
        Task {
            await self.handleNotificationTap(userInfo)
        }
    }

    // Process incoming notification when app is in foreground
    private func processIncomingNotification(_ userInfo: [AnyHashable: Any]) async {
        do {
            let payload = try notificationProcessor.processNotificationPayload(userInfo)
            Logger.debug("Processed notification payload: \(payload)")

            // @lourou: Handle the decrypted notification
            // This is where you'd decrypt XMTP messages, update UI, etc.

        } catch {
            Logger.debug("Failed to process notification payload: \(error)")
        }
    }

    // Handle notification tap navigation
    private func handleNotificationTap(_ userInfo: [AnyHashable: Any]) async {
        do {
            let payload = try notificationProcessor.processNotificationPayload(userInfo)

            // Extract conversation ID for navigation
            let conversationId = notificationProcessor.getConversationIdFromTopic(payload.body.contentTopic)

            // @lourou: Navigate to the conversation
            // You'll need to implement navigation logic here
            // Examples:
            // - Post a notification that your app coordinator can observe
            // - Use a deep link handler
            // - Update a @Published property that your views observe

            Logger.debug("Should navigate to conversation: \(conversationId)")
        } catch {
            Logger.debug("Failed to handle notification tap: \(error)")
        }
    }
}

// MARK: - UIApplication Delegate Adapter

class PushNotificationDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in
            PushNotificationManager.shared.handleDeviceToken(deviceToken)
        }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Task { @MainActor in
            PushNotificationManager.shared.handleRegistrationError(error)
        }
    }

    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        // Handle remote notification
        Logger.debug("Received remote notification: \(userInfo)")

        // Process the notification
        // @lourou: Add your notification handling logic here

        completionHandler(.newData)
    }
}
