import ConvosCore
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
        case "local":
            // For local, use Secrets for API URL if not overridden in config
            let config = ConvosConfiguration(
                apiBaseURL: backendURLOverride ?? Secrets.CONVOS_API_BASE_URL,
                appGroupIdentifier: appGroupIdentifier,
                relyingPartyIdentifier: relyingPartyIdentifier,
                xmtpEndpoint: Secrets.XMTP_CUSTOM_HOST.isEmpty ? nil : Secrets.XMTP_CUSTOM_HOST,
                appCheckToken: Secrets.FIREBASE_APP_CHECK_TOKEN
            )
            return .local(config: config)

        case "dev":
            let config = ConvosConfiguration(
                apiBaseURL: apiBaseURL,
                appGroupIdentifier: appGroupIdentifier,
                relyingPartyIdentifier: relyingPartyIdentifier,
                appCheckToken: Secrets.FIREBASE_APP_CHECK_TOKEN
            )
            return .dev(config: config)

        case "production":
            let config = ConvosConfiguration(
                apiBaseURL: apiBaseURL,
                appGroupIdentifier: appGroupIdentifier,
                relyingPartyIdentifier: relyingPartyIdentifier,
                appCheckToken: Secrets.FIREBASE_APP_CHECK_TOKEN
            )
            return .production(config: config)

        default:
            fatalError("Invalid environment '\(envString)' in config.json")
        }
    }

    /// API base URL from config (optional for local, required for dev/prod)
    var apiBaseURL: String {
        guard let url = config["backendUrl"] as? String else {
            fatalError("Missing 'backendUrl' in config.json")
        }
        return url
    }

    /// Backend URL if specified in config
    var backendURLOverride: String? {
        config["backendUrl"] as? String
    }

    /// Bundle identifier from config
    var bundleIdentifier: String {
        guard let id = config["bundleId"] as? String else {
            fatalError("Missing 'bundleId' in config.json")
        }
        return id
    }

    /// App group identifier from config
    var appGroupIdentifier: String {
        guard let id = config["appGroupIdentifier"] as? String else {
            fatalError("Missing 'appGroupIdentifier' in config.json")
        }
        return id
    }

    /// Relying party identifier from config
    var relyingPartyIdentifier: String {
        guard let id = config["relyingPartyIdentifier"] as? String else {
            fatalError("Missing 'relyingPartyIdentifier' in config.json")
        }
        return id
    }
}
