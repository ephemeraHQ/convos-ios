import Foundation
import UIKit
import UserNotifications

enum PushNotificationError: Error {
    case noInstallations
    case noActiveSession
    case registrationFailed(String)
}

@MainActor
class PushNotificationManager: NSObject, ObservableObject {
    static let shared: PushNotificationManager = PushNotificationManager()

    @Published var deviceToken: String?
    @Published var isAuthorized: Bool = false
    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published var registrationError: Error?

    private let notificationProcessor: NotificationProcessor
    private let convosClient: ConvosClient

    private override init() {
        // Get app group identifier from ConfigManager
        let appGroupId = ConfigManager.shared.currentEnvironment.appGroupIdentifier
        self.notificationProcessor = NotificationProcessor(appGroupIdentifier: appGroupId)
        self.convosClient = ConvosClient.client(environment: ConfigManager.shared.currentEnvironment)

        super.init()

        Task {
            await checkAuthorizationStatus()
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
        await UIApplication.shared.registerForRemoteNotifications()
    }

    // MARK: - Device Token Handling

    func handleDeviceToken(_ deviceToken: Data) {
        let tokenParts = deviceToken.map { data in String(format: "%02.2hhx", data) }
        let token = tokenParts.joined()

        print("Device Token: \(token)")
        self.deviceToken = token

        // Store token in shared storage
        notificationProcessor.storeDeviceToken(token)

        Task {
            await registerDeviceTokenWithBackend(token)
        }
    }

    func handleRegistrationError(_ error: Error) {
        print("Failed to register for remote notifications: \(error)")
        self.registrationError = error
    }

    // MARK: - Backend Registration

    private func registerDeviceTokenWithBackend(_ token: String) async {
        do {
            // Since device is already registered, just register the push token
            try await registerPushToken(token)

            print("Successfully registered push token with backend")
            registrationError = nil
        } catch {
            print("Failed to register push token with backend: \(error)")
            registrationError = error
        }
    }

    private func registerPushToken(_ token: String) async throws {
        // Get current user's installations from the convos client
        let installations = try await getCurrentUserInstallations()

        guard !installations.isEmpty else {
            throw PushNotificationError.noInstallations
        }

        let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString

        let request = PushTokenRegistrationRequest(
            deviceId: deviceId,
            pushToken: token,
            pushTokenType: .apns,
            apnsEnvironment: ConfigManager.shared.currentEnvironment.apnsEnvironment,
            installations: installations
        )

        let response = try await convosClient.registerPushToken(request)
        print("Push token registration response: \(response)")
    }

    private func getCurrentUserInstallations() async throws -> [InstallationInfo] {
        // TODO: Get this from your ConvosClient/SessionManager
        // This should return the current user's identity ID and XMTP installation ID

        // Example (you'll need to implement the actual logic):
        // guard let currentSession = SessionManager.shared.currentSession else {
        //     throw PushNotificationError.noActiveSession
        // }
        // 
        // let identityId = currentSession.identityId
        // let xmtpInstallationId = currentSession.xmtpInstallationId
        // 
        // return [InstallationInfo(identityId: identityId, xmtpInstallationId: xmtpInstallationId)]

        // For now, return empty array - you'll need to implement this
        return []
    }

    // MARK: - Topic Subscription (for future use)

    func subscribeToTopic(_ topic: String) async {
        print("Subscribing to topic: \(topic)")
        notificationProcessor.addSubscribedTopic(topic)

        // TODO: Notify backend about topic subscription
        // This should tell your backend to start sending notifications for this topic
    }

    func unsubscribeFromTopic(_ topic: String) async {
        print("Unsubscribing from topic: \(topic)")
        notificationProcessor.removeSubscribedTopic(topic)

        // TODO: Notify backend about topic unsubscription
        // This should tell your backend to stop sending notifications for this topic
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
        print("Received notification in foreground: \(userInfo)")

        // TODO: Process the notification payload here if needed
        // You might want to decrypt XMTP messages or update local state

        // For now, we'll process the notification in the background
        Task { @MainActor in
            await self.processIncomingNotification(userInfo)
        }

        // Show notification even when app is in foreground
        return [.alert, .badge, .sound]
    }

    // Handle notification tap
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        print("User tapped notification: \(userInfo)")

        // Process the notification tap
        await MainActor.run {
            Task {
                await self.handleNotificationTap(userInfo)
            }
        }
    }

    // Process incoming notification when app is in foreground
    private func processIncomingNotification(_ userInfo: [AnyHashable: Any]) async {
        do {
            let payload = try notificationProcessor.processNotificationPayload(userInfo)
            print("Processed notification payload: \(payload)")

            // TODO: Handle the decrypted notification
            // This is where you'd decrypt XMTP messages, update UI, etc.

        } catch {
            print("Failed to process notification payload: \(error)")
        }
    }

    // Handle notification tap navigation
    private func handleNotificationTap(_ userInfo: [AnyHashable: Any]) async {
        do {
            let payload = try notificationProcessor.processNotificationPayload(userInfo)

            // Extract conversation ID for navigation
            let conversationId = notificationProcessor.getConversationIdFromTopic(payload.body.contentTopic)

            // TODO: Navigate to the conversation
            // You'll need to implement navigation logic here
            // Examples:
            // - Post a notification that your app coordinator can observe
            // - Use a deep link handler
            // - Update a @Published property that your views observe

            print("Should navigate to conversation: \(conversationId)")
        } catch {
            print("Failed to handle notification tap: \(error)")
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
        print("Received remote notification: \(userInfo)")

        // Process the notification
        // TODO: Add your notification handling logic here

        completionHandler(.newData)
    }
}
