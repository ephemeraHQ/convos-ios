import ConvosCore
import SwiftUI

@main
struct ConvosAppClipApp: App {
    let convos: ConvosClient = .client(environment: ConfigManager.shared.currentEnvironment)

    @UIApplicationDelegateAdaptor(ConvosAppDelegate.self) var appDelegate: ConvosAppDelegate

    init() {
        // Configure Logger based on environment
        let environment = ConfigManager.shared.currentEnvironment

        // Configure Logger with proper environment for app group access
        Logger.configure(environment: environment)

        switch environment {
        case .production:
            Logger.Default.configureForProduction(true)
        default:
            Logger.Default.configureForProduction(false)
        }

        Logger.info("🚀 App starting with environment: \(environment)")

        // Pass the session to the app delegate for notification handling
        appDelegate.session = convos.session
    }

    var body: some Scene {
        WindowGroup {
            ConversationsView(session: convos.session)
                .withSafeAreaEnvironment()
        }
    }
}
