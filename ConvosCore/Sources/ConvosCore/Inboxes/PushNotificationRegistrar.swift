import Foundation
import UIKit
import UserNotifications
import XMTPiOS

protocol PushNotificationRegistrarProtocol {
    func registerForRemoteNotifications() async
    func unregisterInstallation(client: any XMTPClientProvider, apiClient: any ConvosAPIClientProtocol) async
}

public final class PushNotificationRegistrar: PushNotificationRegistrarProtocol {
    private let environment: AppEnvironment
    private let keychainService: KeychainService<LastRegisteredPushTokenKeychainItem> = .init()

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    private static var tokenKey: String = "pushToken"

    public static func save(token: String) {
        UserDefaults.standard.set(token, forKey: tokenKey)
        NotificationCenter.default.post(name: .convosPushTokenDidChange, object: nil)
    }

    public static var token: String? {
        UserDefaults.standard.string(forKey: tokenKey)
    }

    func registerForRemoteNotifications() async {
        await MainActor.run {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    /// Requests notification authorization if not already granted, then registers for remote notifications
    /// Can be called from anywhere in the app when user takes an action that would benefit from notifications
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

    func unregisterInstallation(client: any XMTPClientProvider, apiClient: any ConvosAPIClientProtocol) async {
        do {
            try await apiClient.unregisterInstallation(clientId: client.installationId)
            deleteLastUsedPushTokenFromKeychain(for: client.inboxId)
            Logger.info("Unregistered installation: \(client.installationId)")
        } catch {
            // Ignore errors during unregistration
            Logger.info("Could not unregister installation (likely during account deletion): \(error)")
        }
    }

    // MARK: - Private Helpers

    private func deleteLastUsedPushTokenFromKeychain(for inboxId: String) {
        do {
            try keychainService.delete(.init(inboxId: inboxId))
            Logger.debug("Deleted last used push token from keychain (cleanup)")
        } catch {
            Logger.debug("Failed to delete last used push token from keychain: \(error)")
        }
    }
}

// MARK: - Mock Implementation for Testing

final class MockPushNotificationRegistrar: PushNotificationRegistrarProtocol {
    func registerForRemoteNotifications() async {}
    func unregisterInstallation(client: any XMTPClientProvider, apiClient: any ConvosAPIClientProtocol) async {}
}
