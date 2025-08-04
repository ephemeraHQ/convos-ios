import Foundation
import UIKit
import UserNotifications

@MainActor
class PushNotificationManager: NSObject, ObservableObject {
    static let shared = PushNotificationManager()

    @Published var deviceToken: String?
    @Published var isAuthorized = false
    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private override init() {
        super.init()
        Task {
            await checkAuthorizationStatus()
        }
    }

    // MARK: - Authorization

    func checkAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
        isAuthorized = settings.authorizationStatus == .authorized
    }

    func requestAuthorization() async throws {
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])

        await checkAuthorizationStatus()

        if granted {
            await registerForRemoteNotifications()
        }
    }

    // MARK: - Registration

    private func registerForRemoteNotifications() async {
        await UIApplication.shared.registerForRemoteNotifications()
    }

    // MARK: - Device Token Handling

    func handleDeviceToken(_ deviceToken: Data) {
        let tokenParts = deviceToken.map { data in String(format: "%02.2hhx", data) }
        let token = tokenParts.joined()

        print("Device Token: \(token)")
        self.deviceToken = token

        Task {
            await registerDeviceTokenWithBackend(token)
        }
    }

    func handleRegistrationError(_ error: Error) {
        print("Failed to register for remote notifications: \(error)")
    }

    // MARK: - Backend Registration

    private func registerDeviceTokenWithBackend(_ token: String) async {
        // TODO: Implement your backend registration logic here
        print("Registering device token with backend: \(token)")

        // Example structure (you'll need to adapt this to your backend API):
        // do {
        //     let convosClient = ConvosClient.client(environment: ConfigManager.shared.currentEnvironment)
        //     try await convosClient.registerPushToken(token)
        //     print("Successfully registered push token")
        // } catch {
        //     print("Failed to register push token: \(error)")
        // }
    }

    // MARK: - Topic Subscription (for future use)

    func subscribeToTopic(_ topic: String) async {
        // TODO: Implement topic subscription when needed
        // This will be used later for subscribing to specific push notification topics
        print("Subscribing to topic: \(topic)")
    }

    func unsubscribeFromTopic(_ topic: String) async {
        // TODO: Implement topic unsubscription when needed
        print("Unsubscribing from topic: \(topic)")
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension PushNotificationManager: UNUserNotificationCenterDelegate {
    // Handle notifications when app is in foreground
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        // Show notification even when app is in foreground
        return [.alert, .badge, .sound]
    }

    // Handle notification tap
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        print("User tapped notification: \(userInfo)")

        // TODO: Handle notification tap - navigate to specific conversation, etc.
        // You can post a notification or use a coordinator pattern to handle navigation
    }
}

// MARK: - UIApplication Delegate Adapter

class PushNotificationDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in
            PushNotificationManager.shared.handleDeviceToken(deviceToken)
        }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Task { @MainActor in
            PushNotificationManager.shared.handleRegistrationError(error)
        }
    }

    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        // Handle remote notification
        print("Received remote notification: \(userInfo)")

        // Process the notification
        // TODO: Add your notification handling logic here

        completionHandler(.newData)
    }
}
