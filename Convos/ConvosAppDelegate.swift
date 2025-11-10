import ConvosCore
import UIKit
import UserNotifications

// MARK: - App Delegate

/// Lightweight delegate for push notifications and scene configuration
@MainActor
class ConvosAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    var session: (any SessionManagerProtocol)?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        SentryConfiguration.configure()
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let tokenParts = deviceToken.map { data in String(format: "%02.2hhx", data) }
        let token = tokenParts.joined()

        Log.info("Received device token from APNS")
        // Store token in shared storage
        PushNotificationRegistrar.save(token: token)
        Log.info("Stored device token in shared storage")
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Log.error("Failed to register for remote notifications: \(error)")
    }

    // MARK: - UNUserNotificationCenterDelegate

    // Handle notifications when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        // Check if this is an explode notification
        if let explodeInfo = ExplodeNotificationManager.extractConversationInfo(from: notification.request) {
            Log.info("Explode notification fired while app in foreground for conversation: \(explodeInfo.conversationId)")

            // Perform the explosion after a short delay to let the banner show
            Task {
                // Wait for the banner to be shown
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

                await handleConversationExplosion(
                    conversationId: explodeInfo.conversationId,
                    inboxId: explodeInfo.inboxId,
                    clientId: explodeInfo.clientId
                )
            }

            // Show the notification banner for explode notifications
            return [.banner, .sound]
        }

        // Check if we should display this notification based on the active conversation
        let conversationId = notification.request.content.threadIdentifier

        if !conversationId.isEmpty,
           let session = session {
            let shouldDisplay = await session.shouldDisplayNotification(for: conversationId)
            if !shouldDisplay {
                return []
            }
        }

        // Show notification banner when app is in foreground
        // NSE processes all notifications regardless of app state
        Log.info("App in foreground - showing notification banner")
        return [.banner]
    }

    // Handle notification taps
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        Log.debug("Notification tapped")

        // Check if this is an explode notification scheduled by ExplodeNotificationManager
        if let explodeInfo = ExplodeNotificationManager.extractConversationInfo(from: response) {
            Log.info("Explode notification tapped for conversation: \(explodeInfo.conversationId)")

            // Perform the explosion (if not already done)
            await handleConversationExplosion(
                conversationId: explodeInfo.conversationId,
                inboxId: explodeInfo.inboxId,
                clientId: explodeInfo.clientId
            )

            // Post explosion notification which will navigate to conversation list
            // The ConversationsViewModel should handle this by dismissing any presented conversation
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .explosionNotificationTapped,
                    object: nil,
                    userInfo: [
                        "inboxId": explodeInfo.inboxId,
                        "conversationId": explodeInfo.conversationId,
                        "notificationType": "explosion"
                    ]
                )
            }
            return
        }

        // Handle regular conversation notifications (Protocol messages)
        // v2 notifications use clientId, need to look up inboxId from database
        let conversationId = response.notification.request.content.threadIdentifier

        guard !conversationId.isEmpty else {
            Log.warning("Notification tapped but conversationId is empty")
            return
        }

        guard let session = session,
              let inboxId = await session.inboxId(for: conversationId) else {
            Log
                .warning(
                    "Notification tapped but could not find inboxId for conversationId: \(conversationId)"
                )
            return
        }

        Log
            .info(
                "Handling conversation notification tap for inboxId: \(inboxId), conversationId: \(conversationId)"
            )
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .conversationNotificationTapped,
                object: nil,
                userInfo: [
                    "inboxId": inboxId,
                    "conversationId": conversationId
                ]
            )
        }
    }

    // MARK: - Private Methods

    private func handleConversationExplosion(conversationId: String, inboxId: String, clientId: String) async {
        guard let session = session else {
            Log.error("No session available for explosion")
            return
        }

        // Delegate to SessionManager
        await session.explodeConversation(
            conversationId: conversationId,
            inboxId: inboxId,
            clientId: clientId
        )

        // Post notification for UI updates
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .explosionNotificationTapped,
                object: nil,
                userInfo: [
                    "inboxId": inboxId,
                    "conversationId": conversationId,
                    "notificationType": "explosion"
                ]
            )
        }
    }
}
