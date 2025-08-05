import Foundation
import UIKit
import UserNotifications

enum PushNotificationError: Error {
    case noInstallations
    case noActiveSession
    case registrationFailed(String)
    case timeout
}

// Helper function for timeout operations
func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }

        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw PushNotificationError.timeout
        }

        guard let result = try await group.next() else {
            throw PushNotificationError.timeout
        }

        group.cancelAll()
        return result
    }
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

        Logger.info("🔔 [PushNotificationManager] ✅ Received device token from APNS: \(token)")
        self.deviceToken = token

        // Store token in shared storage
        notificationProcessor.storeDeviceToken(token)
        Logger.info("🔔 [PushNotificationManager] ✅ Stored device token in shared storage")

        Task {
            await registerDeviceTokenWithBackend(token)
        }
    }

    // MARK: - Manual Registration (for debugging)

    func manuallyRegisterCurrentToken() async {
        Logger.info("🔔 [PushNotificationManager] Manual push token registration requested")

        guard let currentToken = deviceToken else {
            Logger.error("🔔 [PushNotificationManager] ❌ No device token available for manual registration")
            return
        }

        Logger.info("🔔 [PushNotificationManager] Current device token: \(currentToken)")
        await registerDeviceTokenWithBackend(currentToken)
    }

    // MARK: - Conversation-specific Registration

    func registerPushTokenForNewConversation(inboxId: String) async {
        Logger.info("🔔 [PushNotificationManager] Push token registration requested for new conversation with inboxId: \(inboxId)")

        guard let currentToken = deviceToken else {
            Logger.error("🔔 [PushNotificationManager] ❌ No device token available for conversation registration")
            return
        }

        Logger.info("🔔 [PushNotificationManager] Registering push token for new conversation with token: \(currentToken)")
        await registerPushTokenDirectly(currentToken, inboxId: inboxId)
    }

    func handleRegistrationError(_ error: Error) {
        Logger.error("🔔 [PushNotificationManager] ❌ Failed to register for remote notifications: \(error)")
        self.registrationError = error
    }

    // MARK: - Backend Registration

    private func registerPushTokenDirectly(_ token: String, inboxId: String) async {
        Logger.info("🔔 [PushNotificationManager] Directly registering push token for inboxId: \(inboxId)")
        Logger.info("🔔 [PushNotificationManager] Token: \(token)")

        do {
            let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
            Logger.info("🔔 [PushNotificationManager] Device ID: \(deviceId)")
            Logger.info("🔔 [PushNotificationManager] APNS Environment: \(ConfigManager.shared.currentEnvironment.apnsEnvironment)")

            // Create installation info directly using the inbox ID
            // We don't need the full XMTP client for this - just use a placeholder installation ID
            let installationInfo = InstallationInfo(
                identityId: inboxId,
                xmtpInstallationId: "pending-\(inboxId.prefix(8))" // Temporary until client is ready
            )

            let request = PushTokenRegistrationRequest(
                deviceId: deviceId,
                pushToken: token,
                pushTokenType: .apns,
                apnsEnvironment: ConfigManager.shared.currentEnvironment.apnsEnvironment,
                installations: [installationInfo]
            )

            Logger.info("🔔 [PushNotificationManager] Making direct API call to register push token...")
            let response = try await convosClient.registerPushToken(request)
            Logger.info("🔔 [PushNotificationManager] ✅ Successfully registered push token directly: \(response)")
            registrationError = nil
        } catch {
            Logger.error("🔔 [PushNotificationManager] ❌ Failed to register push token directly: \(error)")
            registrationError = error
        }
    }

    private func registerDeviceTokenWithBackend(_ token: String, specificInboxId: String? = nil) async {
        Logger.info("🔔 [PushNotificationManager] Starting push token registration with backend")
        Logger.info("🔔 [PushNotificationManager] Token: \(token)")
        if let specificInboxId = specificInboxId {
            Logger.info("🔔 [PushNotificationManager] Using specific inboxId: \(specificInboxId)")
        }

        do {
            // Since device is already registered, just register the push token
            try await registerPushToken(token, specificInboxId: specificInboxId)

            Logger.info("🔔 [PushNotificationManager] ✅ Successfully registered push token with backend")
            registrationError = nil
        } catch {
            Logger.error("🔔 [PushNotificationManager] ❌ Failed to register push token with backend: \(error)")
            registrationError = error
        }
    }

    private func registerPushToken(_ token: String, specificInboxId: String? = nil) async throws {
        Logger.info("🔔 [PushNotificationManager] Getting current user installations...")
        if let specificInboxId = specificInboxId {
            Logger.info("🔔 [PushNotificationManager] Using specific inboxId: \(specificInboxId)")
        }

        // Get current user's installations from the convos client
        let installations = try await getCurrentUserInstallations(specificInboxId: specificInboxId)
        Logger.info("🔔 [PushNotificationManager] Found \(installations.count) installations")

        for (index, installation) in installations.enumerated() {
            Logger.info("🔔 [PushNotificationManager] Installation \(index): identityId=\(installation.identityId), xmtpInstallationId=\(installation.xmtpInstallationId)")
        }

        guard !installations.isEmpty else {
            Logger.error("🔔 [PushNotificationManager] ❌ No installations found - throwing noInstallations error")
            throw PushNotificationError.noInstallations
        }

        let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        Logger.info("🔔 [PushNotificationManager] Device ID: \(deviceId)")
        Logger.info("🔔 [PushNotificationManager] APNS Environment: \(ConfigManager.shared.currentEnvironment.apnsEnvironment)")

        let request = PushTokenRegistrationRequest(
            deviceId: deviceId,
            pushToken: token,
            pushTokenType: .apns,
            apnsEnvironment: ConfigManager.shared.currentEnvironment.apnsEnvironment,
            installations: installations
        )

        Logger.info("🔔 [PushNotificationManager] Making API call to register push token...")
        do {
            Logger.info("🔔 [PushNotificationManager] 🚀 About to call convosClient.registerPushToken...")
            let response = try await convosClient.registerPushToken(request)
            Logger.info("🔔 [PushNotificationManager] ✅ Push token registration response: \(response)")
        } catch {
            Logger.error("🔔 [PushNotificationManager] ❌ ConvosClient.registerPushToken failed: \(error)")
            Logger.error("🔔 [PushNotificationManager] ❌ Error type: \(type(of: error))")
            throw error
        }
    }

    private func getCurrentUserInstallations(specificInboxId: String? = nil) async throws -> [InstallationInfo] {
        Logger.info("🔔 [PushNotificationManager] Getting current user installations...")

        let targetInboxId: String

        if let specificInboxId = specificInboxId {
            // Use the specific inbox ID provided
            targetInboxId = specificInboxId
            Logger.info("🔔 [PushNotificationManager] Using specified inbox: \(targetInboxId)")
        } else {
            // Fall back to first inbox
            let allInboxes = try convosClient.session.inboxesRepository.allInboxes()
            Logger.info("🔔 [PushNotificationManager] Found \(allInboxes.count) total inboxes")

            guard let firstInbox = allInboxes.first else {
                Logger.error("🔔 [PushNotificationManager] ❌ No inboxes found - throwing noActiveSession error")
                throw PushNotificationError.noActiveSession
            }

            targetInboxId = firstInbox.inboxId
            Logger.info("🔔 [PushNotificationManager] Using first inbox: \(targetInboxId)")
        }

        let messagingService = convosClient.session.messagingService(for: targetInboxId)
        Logger.info("🔔 [PushNotificationManager] Got messaging service: \(type(of: messagingService))")

        guard let messagingService = messagingService as? MessagingService else {
            Logger.error("🔔 [PushNotificationManager] ❌ Messaging service is not MessagingService type - throwing noActiveSession error")
            throw PushNotificationError.noActiveSession
        }

        Logger.info("🔔 [PushNotificationManager] Waiting for inbox to be ready...")
        // Wait for the inbox to be ready to get the XMTP client with timeout
        var inboxReadyIterator = messagingService.inboxReadyPublisher.values.makeAsyncIterator()

        let inboxReady: InboxReadyResult

        // Try multiple times with increasing timeout for newly created inboxes
        var attempts = 0
        let maxAttempts = 3
        let baseTimeout: TimeInterval = 15

        while attempts < maxAttempts {
            attempts += 1
            let currentTimeout = baseTimeout * Double(attempts) // 15s, 30s, 45s

            Logger.info("🔔 [PushNotificationManager] Attempt \(attempts)/\(maxAttempts) - waiting up to \(currentTimeout)s for inbox to be ready...")

            do {
                let result = try await withTimeout(seconds: currentTimeout) {
                    await inboxReadyIterator.next()
                }
                guard let readyResult = result else {
                    Logger.error("🔔 [PushNotificationManager] ❌ Inbox ready publisher returned nil (attempt \(attempts))")
                    if attempts < maxAttempts {
                        Logger.info("🔔 [PushNotificationManager] 🔄 Retrying in 2 seconds...")
                        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 second delay
                        continue
                    }
                    throw PushNotificationError.noActiveSession
                }
                inboxReady = readyResult
                Logger.info("🔔 [PushNotificationManager] ✅ Inbox ready after \(attempts) attempts!")
                break
            } catch {
                Logger.error("🔔 [PushNotificationManager] ❌ Timeout waiting for inbox to be ready (attempt \(attempts)): \(error)")
                if attempts < maxAttempts {
                    Logger.info("🔔 [PushNotificationManager] 🔄 Retrying in 2 seconds...")
                    try await Task.sleep(nanoseconds: 2_000_000_000) // 2 second delay
                    // Get a fresh iterator for the next attempt
                    inboxReadyIterator = messagingService.inboxReadyPublisher.values.makeAsyncIterator()
                } else {
                    Logger.error("🔔 [PushNotificationManager] ❌ Cannot register push token without ready inbox after \(maxAttempts) attempts")
                    throw error
                }
            }
        }

        Logger.info("🔔 [PushNotificationManager] ✅ Inbox is ready!")
        let xmtpClient = inboxReady.client
        Logger.info("🔔 [PushNotificationManager] XMTP Client inbox ID: \(xmtpClient.inboxId)")
        Logger.info("🔔 [PushNotificationManager] XMTP Client installation ID: \(xmtpClient.installationId)")

        // Create installation info from the XMTP client
        let installationInfo = InstallationInfo(
            identityId: targetInboxId, // Use inbox ID as identity ID
            xmtpInstallationId: xmtpClient.installationId
        )

        Logger.info("🔔 [PushNotificationManager] ✅ Created installation info: identityId=\(installationInfo.identityId), xmtpInstallationId=\(installationInfo.xmtpInstallationId)")

        return [installationInfo]
    }

    // MARK: - Topic Subscription (for future use)

    func subscribeToTopic(_ topic: String) async {
        print("Subscribing to topic: \(topic)")
        notificationProcessor.addSubscribedTopic(topic)

        // @lourou: Notify backend about topic subscription
        // This should tell your backend to start sending notifications for this topic
    }

    func unsubscribeFromTopic(_ topic: String) async {
        print("Unsubscribing from topic: \(topic)")
        notificationProcessor.removeSubscribedTopic(topic)

        // @lourou: Notify backend about topic unsubscription
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

        // @lourou: Process the notification payload here if needed
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

            // @lourou: Handle the decrypted notification
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

            // @lourou: Navigate to the conversation
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
        // @lourou: Add your notification handling logic here

        completionHandler(.newData)
    }
}
