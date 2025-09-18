import ConvosCore
import SwiftUI
import UserNotifications

@main
struct ConvosApp: App {
    @UIApplicationDelegateAdaptor(ConvosAppDelegate.self) private var appDelegate: ConvosAppDelegate
    @Environment(\.scenePhase) private var scenePhase: ScenePhase
    @State private var urlStorage: SceneURLStorage = SceneURLStorage.shared

    let session: any SessionManagerProtocol

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

        if let url = ConfigManager.shared.currentEnvironment.firebaseConfigURL {
            FirebaseHelperCore.configure(with: url)
        } else {
            Logger.error("Missing Firebase plist URL for current environment")
        }
    }

    var body: some Scene {
        WindowGroup {
            ConversationsView(session: session)
                .withSafeAreaEnvironment()
                .onOpenURL { url in
                    handleDeepLink(url)
                }
                .onAppear {
                    // Pass session to app delegate for notification handling
                    appDelegate.session = session

                    // Process any pending URLs from cold launch
                    if let pendingURL = urlStorage.consumePendingURL() {
                        Logger.info("Processing pending URL from cold launch")
                        processDeepLink(pendingURL)
                    }
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            handleScenePhaseChange(newPhase)
        }
    }

    private func handleDeepLink(_ url: URL) {
        // Validate URL before processing
        guard DeepLinkHandler.destination(for: url) != nil else {
            Logger.warning("Invalid deep link received and ignored: [scheme: \(url.scheme ?? "unknown"), host: \(url.host ?? "unknown")]")
            return
        }

        Logger.info("Received valid deep link: [scheme: \(url.scheme ?? "unknown"), host: \(url.host ?? "unknown")]")

        // If app is in background, defer processing until it becomes active
        if scenePhase == .background {
            Logger.info("App in background - deferring deep link processing")
            urlStorage.storePendingURL(url)
            return
        }

        processDeepLink(url)
    }

    private func processDeepLink(_ url: URL) {
        NotificationCenter.default.post(
            name: .deepLinkReceived,
            object: nil,
            userInfo: ["url": url]
        )
    }

    private func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .active:
            Logger.info("App became active")
            // Process any pending deep links now that app is active and stable
            if let pendingURL = urlStorage.consumePendingURL() {
                Logger.info("Processing pending deep link")
                processDeepLink(pendingURL)
            }
        case .inactive:
            Logger.info("App became inactive")
        case .background:
            Logger.info("App moved to background")
        @unknown default:
            break
        }
    }
}
