import SwiftUI

@main
struct ConvosApp: App {
    let convos: ConvosClient = .client(environment: ConfigManager.shared.currentEnvironment)
    let analyticsService: AnalyticsServiceProtocol = PosthogAnalyticsService.shared

    @UIApplicationDelegateAdaptor(PushNotificationDelegate.self) var pushDelegate: PushNotificationDelegate
    @State private var pushNotificationManager: PushNotificationManager = PushNotificationManager.shared

    init() {
        SDKConfiguration.configureSDKs()
        Logger.info("🚀 App starting with environment: \(ConfigManager.shared.currentEnvironment)")
    }

    var body: some Scene {
        WindowGroup {
            ConversationsView(session: convos.session)
                .withSafeAreaEnvironment()
                .environment(pushNotificationManager)
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
                Logger.error("Failed to request push notification authorization: \(error)")
            }
        }
    }
}
