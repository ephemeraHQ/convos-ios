import SwiftUI

@main
struct ConvosApp: App {
    let convos: ConvosClient = .client(environment: .dev)
    let analyticsService: AnalyticsServiceProtocol = PosthogAnalyticsService.shared

    init() {
        SDKConfiguration.configureSDKs()
    }

    var body: some Scene {
        WindowGroup {
            RootView(
                convos: convos,
                analyticsService: analyticsService
            )
        }
    }
}
