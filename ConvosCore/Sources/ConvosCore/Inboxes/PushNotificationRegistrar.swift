import Foundation
import UIKit
import UserNotifications

/// Manages push notification token storage and authorization requests.
/// All methods are static since push token is app-level, not inbox-specific.
public final class PushNotificationRegistrar {
    private static var tokenKey: String = "pushToken"

    /// Saves the push token to UserDefaults and notifies observers of the change.
    /// Called by AppDelegate when APNS token is received.
    public static func save(token: String) {
        UserDefaults.standard.set(token, forKey: tokenKey)
        NotificationCenter.default.post(name: .convosPushTokenDidChange, object: nil)
    }

    /// Returns the current push token from UserDefaults, if available.
    public static var token: String? {
        UserDefaults.standard.string(forKey: tokenKey)
    }

    /// Requests notification authorization if not already granted, then registers for remote notifications.
    /// Can be called from anywhere in the app when user takes an action that would benefit from notifications.
    public static func requestNotificationAuthorizationIfNeeded() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()

        if settings.authorizationStatus == .authorized {
            // Already authorized, just ensure we're registered for remote notifications
            await MainActor.run {
                UIApplication.shared.registerForRemoteNotifications()
            }
            return
        }

        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            if granted {
                // Authorization granted, register for remote notifications to get APNS token
                await MainActor.run {
                    UIApplication.shared.registerForRemoteNotifications()
                }
                Logger.info("Notification authorization granted, registering for remote notifications")
            } else {
                Logger.info("Notification authorization denied by user")
            }
        } catch {
            Logger.warning("Notification authorization failed: \(error)")
        }
    }
}
