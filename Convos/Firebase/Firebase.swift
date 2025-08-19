import ConvosCore
import FirebaseCore
import Foundation

enum FirebaseSetup {
    static func configure() {
        let environment = ConfigManager.shared.currentEnvironment
        guard let url = environment.firebaseConfigURL,
              let options = FirebaseOptions(contentsOfFile: url.path) else {
            Logger.error("Failed to locate or parse Firebase options plist for environment: \(environment.name)")
            return
        }

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
