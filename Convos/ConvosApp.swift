import SwiftUI

@main
struct ConvosApp: App {
    let convos: ConvosClient = .client(environment: ConfigManager.shared.currentEnvironment)
    let analyticsService: AnalyticsServiceProtocol = PosthogAnalyticsService.shared

    init() {
        SDKConfiguration.configureSDKs()

        Logger.info("🚀 App starting with environment: \(ConfigManager.shared.currentEnvironment)")

        do {
            try convos.prepare()
        } catch {
            Logger.error("Convos SDK failed preparing: \(error.localizedDescription)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ConversationsView(session: convos.session)
                .withSafeAreaEnvironment()
        }
    }
}
