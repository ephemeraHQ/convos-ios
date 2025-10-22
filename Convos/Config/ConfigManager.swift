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
    lazy var currentEnvironment: AppEnvironment = {
        guard let envString = config["environment"] as? String else {
            fatalError("Missing 'environment' key in config.json")
        }

        let environment: AppEnvironment

        switch envString {
        case "local":
            // For local, use Secrets for API URL (from .env or auto-detected IP), fallback to config.json
            let effectiveApiUrl = Secrets.CONVOS_API_BASE_URL.isEmpty ? (backendURLOverride ?? "") : Secrets.CONVOS_API_BASE_URL
            let config = ConvosConfiguration(
                apiBaseURL: effectiveApiUrl,
                appGroupIdentifier: appGroupIdentifier,
                relyingPartyIdentifier: relyingPartyIdentifier,
                xmtpEndpoint: Secrets.XMTP_CUSTOM_HOST.isEmpty ? nil : Secrets.XMTP_CUSTOM_HOST,
            )
            environment = .local(config: config)

        case "dev":
            let config = ConvosConfiguration(
                apiBaseURL: apiBaseURL,
                appGroupIdentifier: appGroupIdentifier,
                relyingPartyIdentifier: relyingPartyIdentifier,
            )
            environment = .dev(config: config)

        case "production":
            let config = ConvosConfiguration(
                apiBaseURL: apiBaseURL,
                appGroupIdentifier: appGroupIdentifier,
                relyingPartyIdentifier: relyingPartyIdentifier,
            )
            environment = .production(config: config)

        default:
            fatalError("Invalid environment '\(envString)' in config.json")
        }

        // Store the environment configuration securely for the notification extension
        environment.storeSecureConfigurationForNotificationExtension()

        return environment
    }()

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

    /// Associated domain from config (matches ASSOCIATED_DOMAIN from xcconfig)
    var associatedDomain: String {
        guard let domain = config["associatedDomain"] as? String else {
            fatalError("Missing 'associatedDomain' in config.json")
        }
        return domain
    }

    /// App URL scheme from config
    var appUrlScheme: String {
        guard let scheme = config["appUrlScheme"] as? String else {
            fatalError("Missing 'appUrlScheme' in config.json")
        }
        return scheme
    }
}
