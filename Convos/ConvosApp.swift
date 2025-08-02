import SwiftUI

@main
struct ConvosApp: App {
//    let convos: ConvosClient = .client(environment: ConfigManager.shared.currentEnvironment)
    let analyticsService: AnalyticsServiceProtocol = PosthogAnalyticsService.shared

    init() {
        SDKConfiguration.configureSDKs()
    }

    var body: some Scene {
        WindowGroup {
            ConversationViewTest()
//            RootView(
//                convos: convos,
//                analyticsService: analyticsService
//            )
        }
    }
}
