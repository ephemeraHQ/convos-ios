import Foundation
import UIKit
import UserNotifications
import XMTPiOS

protocol PushNotificationRegistrarProtocol {
    func registerForRemoteNotifications() async
    func requestNotificationAuthorizationIfNeeded() async
    func requestAuthAndRegisterIfNeeded(client: any XMTPClientProvider, apiClient: any ConvosAPIClientProtocol) async
    func registerForNotificationsIfNeeded(client: any XMTPClientProvider, apiClient: any ConvosAPIClientProtocol) async
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
    }

    public static var token: String? {
        UserDefaults.standard.string(forKey: tokenKey)
    }

    public static func clearToken() {
        UserDefaults.standard.removeObject(forKey: tokenKey)
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

    func requestAuthAndRegisterIfNeeded(client: any XMTPClientProvider, apiClient: any ConvosAPIClientProtocol) async {
        await requestNotificationAuthorizationIfNeeded()
        await registerForNotificationsIfNeeded(client: client, apiClient: apiClient)
    }

    func registerForNotificationsIfNeeded(client: any XMTPClientProvider, apiClient: any ConvosAPIClientProtocol) async {
        guard let token = Self.token, !token.isEmpty else { return }

        let identityId = client.inboxId
        let lastRegisteredPushToken = lastSavedPushToken(for: identityId)
        guard token != lastRegisteredPushToken else {
            return
        }

        let deviceId = await currentDeviceId()
        let installationId = client.installationId
        do {
            try await apiClient.registerForNotifications(deviceId: deviceId,
                                                         pushToken: token,
                                                         identityId: identityId,
                                                         xmtpInstallationId: installationId)
            Logger.info("Registered notifications mapping for deviceId=\(deviceId), inboxId=\(identityId)")
            savePushToken(token, for: identityId)
        } catch {
            Logger.error("Failed to register notifications mapping: \(error)")
        }
    }

    func unregisterInstallation(client: any XMTPClientProvider, apiClient: any ConvosAPIClientProtocol) async {
        do {
            try await apiClient.unregisterInstallation(xmtpInstallationId: client.installationId)
            deleteLastUsedPushTokenFromKeychain(for: client.inboxId)
            Logger.info("Unregistered installation: \(client.installationId)")
        } catch {
            Logger.error("Failed to unregister installation: \(error)")
        }
    }

    // MARK: - Private Helpers

    private func currentDeviceId() async -> String {
        await MainActor.run { DeviceInfo.deviceIdentifier }
    }

    private func lastSavedPushToken(for inboxId: String) -> String? {
        do {
            return try keychainService.retrieveString(.init(inboxId: inboxId))
        } catch {
            Logger.debug("Last saved push token not found in keychain: \(error)")
            return nil
        }
    }

    private func savePushToken(_ token: String, for inboxId: String) {
        do {
            try keychainService.saveString(token, for: .init(inboxId: inboxId))
            Logger.info("Saved push token to keychain: \(inboxId)")
        } catch {
            Logger.error("Failed to save push token to keychain: \(error)")
        }
    }

    private func deleteLastUsedPushTokenFromKeychain(for inboxId: String) {
        do {
            try keychainService.delete(.init(inboxId: inboxId))
            Logger.debug("Deleted last used push token from keychain")
        } catch {
            Logger.debug("Failed to delete last used push token from keychain: \(error)")
        }
    }
}

// MARK: - Mock Implementation for Testing

final class MockPushNotificationRegistrar: PushNotificationRegistrarProtocol {
    func registerForRemoteNotifications() async {}
    func requestNotificationAuthorizationIfNeeded() async {}
    func requestAuthAndRegisterIfNeeded(client: any XMTPClientProvider, apiClient: any ConvosAPIClientProtocol) async {}
    func registerForNotificationsIfNeeded(client: any XMTPClientProvider, apiClient: any ConvosAPIClientProtocol) async {}
    func unregisterInstallation(client: any XMTPClientProvider, apiClient: any ConvosAPIClientProtocol) async {}
}
