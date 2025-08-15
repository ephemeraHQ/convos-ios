import ConvosCore
import Foundation
import UIKit
import UserNotifications

@Observable
class PushNotificationManager: NSObject {
    static let shared: PushNotificationManager = .init()
    private(set) var deviceToken: String?

    private let notificationProcessor: NotificationProcessor

    override private init() {
        // Get app group identifier from ConfigManager
        let appGroupId = ConfigManager.shared.currentEnvironment.appGroupIdentifier
        self.notificationProcessor = NotificationProcessor(appGroupIdentifier: appGroupId)

        super.init()

        // Set notification center delegate early so foreground notifications are handled
        UNUserNotificationCenter.current().delegate = self
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

    func handleRegistrationError(_ error: Error) {
        Logger.error("❌ Failed to register for remote notifications: \(error)")
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension PushNotificationManager: UNUserNotificationCenterDelegate {
    // Handle notifications when app is in foreground
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        let userInfo = notification.request.content.userInfo
        Logger.debug("Received notification in foreground: \(userInfo)")

        // Show notification even when app is in foreground
        return [.banner, .badge, .sound]
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
