import ConvosCore
import Foundation
import UIKit
import UserNotifications

@Observable
class PushNotificationManager: NSObject {
    static let shared: PushNotificationManager = .init()

    private override init() {
        super.init()

        // Set notification center delegate early so foreground notifications are handled
        UNUserNotificationCenter.current().delegate = self
    }

    // MARK: - Device Token Handling

    func handleDeviceToken(_ deviceToken: Data) {
        let tokenParts = deviceToken.map { data in String(format: "%02.2hhx", data) }
        let token = tokenParts.joined()

        Logger.info("Received device token from APNS: \(token)")
        // Store token in shared storage
        PushNotificationRegistrar.save(token: token)
        Logger.info("Stored device token in shared storage")

        // Notify listeners that token changed so session-ready components can push it to backend
        NotificationCenter.default.post(name: .convosPushTokenDidChange, object: nil)
    }

    func handleRegistrationError(_ error: Error) {
        Logger.error("Failed to register for remote notifications: \(error)")
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension PushNotificationManager: UNUserNotificationCenterDelegate {
    // Handle notifications when app is in foreground
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        let userInfo = notification.request.content.userInfo
        Logger.debug("Received notification in foreground: \(userInfo)")

        // Don't show notification when app is in foreground
        // This forces ALL notifications to go through NSE for processing
        Logger.info("App in foreground - notification will be processed by NSE instead")
        return []
    }

    // Handle notification taps
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        Logger.debug("Notification tapped: \(userInfo)")

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
        }
    }
}

// MARK: - UIApplication Delegate Adapter

@MainActor
class PushNotificationDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushNotificationManager.shared.handleDeviceToken(deviceToken)
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        PushNotificationManager.shared.handleRegistrationError(error)
    }
}
