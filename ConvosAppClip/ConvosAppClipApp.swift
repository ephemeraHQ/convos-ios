import ConvosCore
import SwiftUI

@main
struct ConvosAppClipApp: App {
    @UIApplicationDelegateAdaptor(ConvosAppDelegate.self) private var appDelegate: ConvosAppDelegate

    let session: any SessionManagerProtocol
    let conversationsViewModel: ConversationsViewModel

    init() {
        let environment = ConfigManager.shared.currentEnvironment
        Logger.configure(environment: environment)

        switch environment {
        case .production:
            Logger.Default.configureForProduction(true)
        default:
            Logger.Default.configureForProduction(false)
        }

        Logger.info("App starting with environment: \(environment)")

        // Configure Firebase BEFORE creating ConvosClient
        // This prevents a race condition where SessionManager tries to use AppCheck before it's configured
        if let url = ConfigManager.shared.currentEnvironment.firebaseConfigURL {
            FirebaseHelperCore.configure(with: url)
        } else {
            Logger.error("Missing Firebase plist URL for current environment")
        }

        let convos: ConvosClient = .client(environment: environment)
        self.session = convos.session
        self.conversationsViewModel = .init(session: session)
        appDelegate.session = session
    }

    var body: some Scene {
        WindowGroup {
            ConversationsView(viewModel: conversationsViewModel)
                .withSafeAreaEnvironment()
        }
    }
}
