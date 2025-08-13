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

    private override init() {
        // Get app group identifier from ConfigManager
        let appGroupId = ConfigManager.shared.currentEnvironment.appGroupIdentifier
        self.notificationProcessor = NotificationProcessor(appGroupIdentifier: appGroupId)
        super.init()

        // Set notification center delegate early so foreground notifications are handled
        UNUserNotificationCenter.current().delegate = self

        Task { await checkAuthorizationStatus() }
    }

    // MARK: - Authorization

    func checkAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
        isAuthorized = settings.authorizationStatus == .authorized
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

        // Notify listeners that token changed so session-ready components can push it to backend
        NotificationCenter.default.post(name: .convosPushTokenDidChange, object: nil)
    }

    // MARK: - Manual Registration

    func handleRegistrationError(_ error: Error) {
        Logger.error("❌ Failed to register for remote notifications: \(error)")
        self.registrationError = error
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
