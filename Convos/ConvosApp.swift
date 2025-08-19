import ConvosCore
import SwiftUI

@main
struct ConvosApp: App {
    let convos: ConvosClient = .client(environment: ConfigManager.shared.currentEnvironment)

    @UIApplicationDelegateAdaptor(PushNotificationDelegate.self) var pushDelegate: PushNotificationDelegate
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

        // TEMPORARY: Wipe keychain data to fix access group migration
        // Remove this after testing!
        #if DEBUG
        // Logger.warning("🚨 TEMPORARY: Wiping keychain data for testing")
        // let authService = SecureEnclaveAuthService(accessGroup: environment.keychainAccessGroup)
        // authService.debugWipeAllKeychainData()
        #endif

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
