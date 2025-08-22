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

final class PushNotificationRegistrar: PushNotificationRegistrarProtocol {
    private let environment: AppEnvironment
    private let authService: any LocalAuthServiceProtocol
    private let inbox: any AuthServiceInboxType

    init(
        environment: AppEnvironment,
        authService: any LocalAuthServiceProtocol,
        inbox: any AuthServiceInboxType
    ) {
        self.environment = environment
        self.authService = authService
        self.inbox = inbox
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
        // TODO: store and get device token in a better way
        let notifProcessor = NotificationProcessor(appGroupIdentifier: environment.appGroupIdentifier)
        guard let token = notifProcessor.getStoredDeviceToken(), !token.isEmpty else { return }

        let deviceId = await currentDeviceId()
        let identityId = client.inboxId
        let installationId = client.installationId
        do {
            try await apiClient.registerForNotifications(deviceId: deviceId,
                                                         pushToken: token,
                                                         identityId: identityId,
                                                         xmtpInstallationId: installationId)
            Logger.info("Registered notifications mapping for deviceId=\(deviceId), installationId=\(installationId)")
        } catch {
            Logger.error("Failed to register notifications mapping: \(error)")
        }
    }

    func unregisterInstallation(client: any XMTPClientProvider, apiClient: any ConvosAPIClientProtocol) async {
        do {
            try await apiClient.unregisterInstallation(xmtpInstallationId: client.installationId)
            Logger.info("Unregistered installation: \(client.installationId)")
        } catch {
            Logger.error("Failed to unregister installation: \(error)")
        }
    }

    // MARK: - Private Helpers

    private func currentDeviceId() async -> String {
        await MainActor.run { DeviceInfo.deviceIdentifier }
    }
}

// MARK: - Mock Implementation for Testing

final class MockPushNotificationRegistrar: PushNotificationRegistrarProtocol {
    func registerForRemoteNotifications() async {}
    func requestNotificationAuthorizationIfNeeded() async {}
    func requestAuthAndRegisterIfNeeded(client: any XMTPClientProvider, apiClient: any ConvosAPIClientProtocol) async {}
    func registerForNotificationsIfNeeded(client: any XMTPClientProvider, apiClient: any ConvosAPIClientProtocol) async {}
    func unsubscribeFromConversation(conversationId: String, client: any XMTPClientProvider, apiClient: any ConvosAPIClientProtocol) async {}
    func unregisterInstallation(client: any XMTPClientProvider, apiClient: any ConvosAPIClientProtocol) async {}
}
