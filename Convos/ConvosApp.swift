import SwiftUI

@main
struct ConvosApp: App {
    let convos: ConvosClient = .client(environment: .otrDev)
    let analyticsService: AnalyticsServiceProtocol = PosthogAnalyticsService.shared

    init() {
        setenv("CFNETWORK_DIAGNOSTICS", "3", 1)
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
