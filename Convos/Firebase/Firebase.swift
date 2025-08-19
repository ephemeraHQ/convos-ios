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
    }
}
