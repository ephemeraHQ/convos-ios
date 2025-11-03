import ConvosCore
import Foundation

/// Simple config loader that overrides AppEnvironment values per build
final class ConfigManager {
    static let shared: ConfigManager = ConfigManager()

    private let config: [String: Any]
    private var _currentEnvironment: AppEnvironment?
    private let environmentLock: NSLock = NSLock()

    private init() {
        guard let url = Bundle.main.url(forResource: "config", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            fatalError("Missing or malformed config.json - ensure build phase copies correct config file")
        }
        self.config = dict
    }

    /// Get the current AppEnvironment from config (thread-safe)
    var currentEnvironment: AppEnvironment {
        environmentLock.lock()
        defer { environmentLock.unlock() }

        if let environment = _currentEnvironment {
            return environment
        }

        let environment = createEnvironment()
        _currentEnvironment = environment
        return environment
    }

    private func resolveAndValidateURL(secretsOverride: String, configDefault: String?, environmentName: String) -> String {
        let url = secretsOverride.isEmpty ? (configDefault ?? "") : secretsOverride
        guard !url.isEmpty else {
            fatalError("Missing 'backendUrl' for \(environmentName) environment (Secrets or config.json)")
        }
        guard URL(string: url) != nil else {
            fatalError("Invalid API URL for \(environmentName) environment: '\(url)'")
        }
        return url
    }

    private func createEnvironment() -> AppEnvironment {
        guard let envString = config["environment"] as? String else {
            fatalError("Missing 'environment' key in config.json")
        }

        let environment: AppEnvironment

        // Two-tier priority: Bash script (generate-secrets-local.sh) writes prioritized value to Secrets.
        // Priority: .env > auto-detected IP > config.json
        // This code: Use Secrets if non-empty, else fallback to config.json (safety when Secrets fails)
        switch envString {
        case "local":
            let url = resolveAndValidateURL(
                secretsOverride: Secrets.CONVOS_API_BASE_URL,
                configDefault: apiBaseURL,
                environmentName: "local"
            )
            let config = ConvosConfiguration(
                apiBaseURL: url,
                appGroupIdentifier: appGroupIdentifier,
                relyingPartyIdentifier: relyingPartyIdentifier,
                xmtpEndpoint: Secrets.XMTP_CUSTOM_HOST.isEmpty ? nil : Secrets.XMTP_CUSTOM_HOST,
                xmtpNetwork: xmtpNetwork
                // @lourou: Enable when ready for XMTP v4 d14n
                // gatewayUrl: Secrets.GATEWAY_URL.isEmpty ? nil : Secrets.GATEWAY_URL
            )
            environment = .local(config: config)

        case "dev":
            // Allow override via Secrets for dev environment (useful for local backend testing)
            let url = resolveAndValidateURL(
                secretsOverride: Secrets.CONVOS_API_BASE_URL,
                configDefault: apiBaseURL,
                environmentName: "dev"
            )
            let config = ConvosConfiguration(
                apiBaseURL: url,
                appGroupIdentifier: appGroupIdentifier,
                relyingPartyIdentifier: relyingPartyIdentifier,
                xmtpEndpoint: Secrets.XMTP_CUSTOM_HOST.isEmpty ? nil : Secrets.XMTP_CUSTOM_HOST,
                xmtpNetwork: xmtpNetwork
            )
            environment = .dev(config: config)

        case "production":
            let url = resolveAndValidateURL(
                secretsOverride: Secrets.CONVOS_API_BASE_URL,
                configDefault: apiBaseURL,
                environmentName: "production"
            )
            let config = ConvosConfiguration(
                apiBaseURL: url,
                appGroupIdentifier: appGroupIdentifier,
                relyingPartyIdentifier: relyingPartyIdentifier,
                xmtpNetwork: xmtpNetwork
            )
            environment = .production(config: config)

        default:
            fatalError("Invalid environment '\(envString)' in config.json")
        }

        // Store the environment configuration securely for the notification extension
        environment.storeSecureConfigurationForNotificationExtension()

        return environment
    }

    /// API base URL from config.json (used as default/fallback when Secrets not provided)
    var apiBaseURL: String? {
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

    /// XMTP Network from config (optional)
    var xmtpNetwork: String? {
        config["xmtpNetwork"] as? String
    }
}
