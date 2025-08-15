import SwiftUI
import ConvosCore

@main
struct ConvosApp: App {
    let convos: ConvosClient = .client(environment: ConfigManager.shared.currentEnvironment)

    @UIApplicationDelegateAdaptor(PushNotificationDelegate.self) var pushDelegate: PushNotificationDelegate
    @State private var pushNotificationManager: PushNotificationManager = .init()

    init() {
        // Configure Logger based on environment
        let environment = ConfigManager.shared.currentEnvironment
        switch environment {
        case .production:
            Logger.Default.configureForProduction(true)
        default:
            Logger.Default.configureForProduction(false)
        }

        // Configure NotificationProcessor with app group
        NotificationProcessor.configure(appGroupIdentifier: environment.appGroupIdentifier)

        Logger.info("🚀 App starting with environment: \(environment)")

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
                .environment(pushNotificationManager)
        }
    }
}
