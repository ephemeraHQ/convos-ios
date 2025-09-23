import ConvosCore
import SwiftUI
import UserNotifications

@main
struct ConvosApp: App {
    @UIApplicationDelegateAdaptor(ConvosAppDelegate.self) private var appDelegate: ConvosAppDelegate
    @Environment(\.scenePhase) private var scenePhase: ScenePhase
    @State private var urlStorage: SceneURLStorage = SceneURLStorage.shared

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

        let convos: ConvosClient = .client(environment: environment)
        self.session = convos.session
        self.conversationsViewModel = .init(session: session)
        appDelegate.session = session

        if let url = ConfigManager.shared.currentEnvironment.firebaseConfigURL {
            FirebaseHelperCore.configure(with: url)
        } else {
            Logger.error("Missing Firebase plist URL for current environment")
        }
    }

    var body: some Scene {
        WindowGroup {
            ConversationsView(viewModel: conversationsViewModel)
                .withSafeAreaEnvironment()
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL {
                        handleDeepLink(url)
                    }
                }
                .onOpenURL { url in
                    handleDeepLink(url)
                }
        }
    }

    private func handleDeepLink(_ url: URL) {
        // Validate URL before processing
        guard DeepLinkHandler.destination(for: url) != nil else {
            Logger.warning("Invalid deep link received and ignored: [scheme: \(url.scheme ?? "unknown"), host: \(url.host ?? "unknown")]")
            return
        }

        Logger.info("Received valid deep link: [scheme: \(url.scheme ?? "unknown"), host: \(url.host ?? "unknown")]")
        NotificationCenter.default.post(
            name: .deepLinkReceived,
            object: nil,
            userInfo: ["url": url]
        )
    }
}
