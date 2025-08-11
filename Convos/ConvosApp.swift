import SwiftUI

@main
struct ConvosApp: App {
    let convos: ConvosClient = .client(environment: ConfigManager.shared.currentEnvironment)
    let analyticsService: AnalyticsServiceProtocol = PosthogAnalyticsService.shared

    @UIApplicationDelegateAdaptor(PushNotificationDelegate.self) var pushDelegate: PushNotificationDelegate
    @StateObject private var pushNotificationManager: PushNotificationManager = PushNotificationManager.shared

    init() {
        SDKConfiguration.configureSDKs()

        // Initialize Logger with correct production flag
        let isProduction = ConfigManager.shared.currentEnvironment == .production
        _ = Logger.Default(isProduction: isProduction)

        Logger.info("🚀 App starting with environment: \(ConfigManager.shared.currentEnvironment)")
    }

    var body: some Scene {
        WindowGroup {
            ConversationsView(session: convos.session)
            .withSafeAreaEnvironment()
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

                // Also try to register existing token if we have one and user sessions are ready
                await pushNotificationManager.manuallyRegisterCurrentToken()
            } catch {
                Logger.error("🔔 [PushNotificationManager] ❌ Failed to request push notification authorization: \(error)")
            }
        }
    }
}
