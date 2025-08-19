import ConvosCore
import FirebaseAppCheck
import FirebaseCore
import Foundation

final class AppAttestFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
        AppAttestProvider(app: app)
    }
}

enum FirebaseSetup {
    static func configure() {
        let environment = ConfigManager.shared.currentEnvironment
        guard let url = environment.firebaseConfigURL,
              let options = FirebaseOptions(contentsOfFile: url.path) else {
            Logger.error("Failed to locate or parse Firebase options plist for environment: \(environment.name)")
            return
        }
        AppCheck.setAppCheckProviderFactory(AppAttestFactory())
        FirebaseApp.configure(options: options)
        // Verification logs using Firebase SDK
        if let app = FirebaseApp.app() {
            let projectId = app.options.projectID ?? "unknown"
            let appId = app.options.googleAppID
            Logger.info("✅ Firebase configured. projectId=\(projectId), appId=\(appId)")
        } else {
            Logger.error("❌ Firebase is not configured")
        }
    }
}
