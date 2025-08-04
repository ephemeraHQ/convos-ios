import SwiftUI

@main
struct ConvosApp: App {
    let convos: ConvosClient = .client(environment: ConfigManager.shared.currentEnvironment)
    let analyticsService: AnalyticsServiceProtocol = PosthogAnalyticsService.shared

    @UIApplicationDelegateAdaptor(PushNotificationDelegate.self) var pushDelegate
    @StateObject private var pushNotificationManager = PushNotificationManager.shared

    init() {
        SDKConfiguration.configureSDKs()
    }

    var body: some Scene {
        WindowGroup {
            RootView(
                convos: convos,
                analyticsService: analyticsService
            )
            .environmentObject(pushNotificationManager)
            .onAppear {
                setupPushNotifications()
            }
        }
    }

    private func setupPushNotifications() {
        Task {
            do {
                try await pushNotificationManager.requestAuthorization()
            } catch {
                print("Failed to request push notification authorization: \(error)")
            }
        }
    }
}
