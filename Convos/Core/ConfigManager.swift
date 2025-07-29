import Foundation

/// Simple config loader that overrides AppEnvironment values per build
final class ConfigManager {
    static let shared: ConfigManager = ConfigManager()

    private let config: [String: Any]

    private init() {
        guard let url = Bundle.main.url(forResource: "config", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            fatalError("Missing or malformed config.json - ensure build phase copies correct config file")
        }
        self.config = dict
    }

    /// Get the current AppEnvironment from config
    var currentEnvironment: AppEnvironment {
        guard let envString = config["environment"] as? String else {
            fatalError("Missing 'environment' key in config.json")
        }

        switch envString {
        case "local": return .local
        case "dev": return .dev
        case "production": return .production
        default:
            fatalError("Invalid environment '\(envString)' in config.json")
        }
    }

    /// Override backend URL if specified in config
    var backendURLOverride: String? {
        config["backendUrl"] as? String
    }

    /// Override bundle identifier if specified
    var bundleIdOverride: String? {
        config["bundleId"] as? String
    }

    /// Override app group identifier if specified
    var appGroupOverride: String? {
        config["appGroupIdentifier"] as? String
    }

    /// Override relying party identifier if specified
    var relyingPartyOverride: String? {
        config["relyingPartyIdentifier"] as? String
    }
}
