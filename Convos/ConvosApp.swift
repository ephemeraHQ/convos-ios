import SwiftUI

@main
struct ConvosApp: App {
    let convos: ConvosClient = .client(environment: ConfigManager.shared.currentEnvironment)
    let analyticsService: AnalyticsServiceProtocol = PosthogAnalyticsService.shared

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
        }
    }
}
