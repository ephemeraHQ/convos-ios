import ConvosCore
import SwiftUI

@main
struct ConvosApp: App {
    let convos: ConvosClient = .client(environment: ConfigManager.shared.currentEnvironment)

    @UIApplicationDelegateAdaptor(ConvosAppDelegate.self) var appDelegate: ConvosAppDelegate
    @State private var pushNotificationManager: PushNotificationManager = .shared

    init() {
        // Configure Logger based on environment
        let environment = ConfigManager.shared.currentEnvironment
        switch environment {
        case .production:
            Logger.Default.configureForProduction(true)
        default:
            Logger.Default.configureForProduction(false)
        }

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

// MARK: - UIApplication Delegate Adapter

@MainActor
class ConvosAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                       didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        FirebaseSetup.configure()

        return true
    }
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushNotificationManager.shared.handleDeviceToken(deviceToken)
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        PushNotificationManager.shared.handleRegistrationError(error)
    }
}
