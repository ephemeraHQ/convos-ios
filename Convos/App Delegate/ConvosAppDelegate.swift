import ConvosCore
import Foundation
import UIKit
import UserNotifications

// MARK: - UIApplication Delegate Adapter

@MainActor
class ConvosAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self

        if let url = ConfigManager.shared.currentEnvironment.firebaseConfigURL {
            FirebaseHelperCore.configure(with: url)
        } else {
            Logger.error("Missing Firebase plist URL for current environment")
        }

        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let tokenParts = deviceToken.map { data in String(format: "%02.2hhx", data) }
        let token = tokenParts.joined()

        Logger.info("Received device token from APNS: \(token)")
        // Store token in shared storage
        PushNotificationRegistrar.save(token: token)
        Logger.info("Stored device token in shared storage")

        // Notify listeners that token changed so session-ready components can push it to backend
        NotificationCenter.default.post(name: .convosPushTokenDidChange, object: nil)
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Logger.error("Failed to register for remote notifications: \(error)")
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension ConvosAppDelegate: UNUserNotificationCenterDelegate {
    // Handle notifications when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        // Show notification banner when app is in foreground
        // NSE processes all notifications regardless of app state
        Logger.info("App in foreground - showing notification banner")
        return [.banner]
    }

    // Handle notification taps
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        Logger.debug("Notification tapped")

        // Parse the push notification payload to extract conversation info
        let payload = PushNotificationPayload(userInfo: userInfo)

        // Check if this is an explosion notification
        if let notificationType = userInfo["notificationType"] as? String,
           notificationType == "explosion",
           let inboxId = userInfo["inboxId"] as? String,
           let conversationId = userInfo["conversationId"] as? String {
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .explosionNotificationTapped,
                    object: nil,
                    userInfo: [
                        "inboxId": inboxId,
                        "conversationId": conversationId,
                        "notificationType": notificationType
                    ]
                )
            }
            return
        }

        // Handle regular conversation notifications (Protocol messages)
        if let inboxId = payload.inboxId,
           let conversationId = payload.notificationData?.protocolData?.conversationId {
            Logger.info("Handling conversation notification tap for inboxId: \(inboxId), conversationId: \(conversationId)")
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
        } else {
            Logger.warning("Notification tapped but could not extract conversation info from payload")
        }
    }
}
