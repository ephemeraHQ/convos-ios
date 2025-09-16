import ConvosCore
import Foundation
import UIKit
import UserNotifications

// MARK: - UIApplication Delegate Adapter

@MainActor
class ConvosAppDelegate: NSObject, UIApplicationDelegate {
    var session: (any SessionManagerProtocol)?
    static var pendingDeepLink: URL?

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

    // Handle URL opening when app is launched or brought to foreground
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        Logger.info("AppDelegate: Received URL: \(url)")
        // Store the URL for processing
        ConvosAppDelegate.pendingDeepLink = url
        // Post notification that URL was received
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .deepLinkReceived,
                object: nil,
                userInfo: ["url": url]
            )
        }
        return true
    }

    // Handle Universal Links
    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
              let url = userActivity.webpageURL else {
            return false
        }

        Logger.info("AppDelegate: Received Universal Link: \(url)")
        // Store the URL for processing
        ConvosAppDelegate.pendingDeepLink = url
        // Post notification that URL was received
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .deepLinkReceived,
                object: nil,
                userInfo: ["url": url]
            )
        }
        return true
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension ConvosAppDelegate: UNUserNotificationCenterDelegate {
    // Handle notifications when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
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
        let conversationId = response.notification.request.content.threadIdentifier
        if let inboxId = payload.inboxId {
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
