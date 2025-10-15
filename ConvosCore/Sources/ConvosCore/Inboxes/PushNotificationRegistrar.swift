import Foundation
import UIKit
import UserNotifications
import XMTPiOS

protocol PushNotificationRegistrarProtocol {
    func registerForRemoteNotifications() async
    func requestNotificationAuthorizationIfNeeded() async
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

    func requestNotificationAuthorizationIfNeeded() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus != .authorized else {
            return
        }

        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
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
    func requestNotificationAuthorizationIfNeeded() async {}
    func unregisterInstallation(client: any XMTPClientProvider, apiClient: any ConvosAPIClientProtocol) async {}
}
