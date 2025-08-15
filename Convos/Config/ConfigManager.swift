import Foundation
import ConvosCore

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
            let config = ConvosConfiguration(
                apiBaseURL: backendURLOverride ?? Secrets.CONVOS_API_BASE_URL,
                appGroupIdentifier: appGroupOverride ?? "group.org.convos.ios-local",
                relyingPartyIdentifier: relyingPartyOverride ?? "local.convos.org",
                xmtpEndpoint: Secrets.XMTP_CUSTOM_HOST.isEmpty ? nil : Secrets.XMTP_CUSTOM_HOST,
                appCheckToken: Secrets.FIREBASE_APP_CHECK_TOKEN
            )
            return .local(config: config)

        case "dev":
            let config = ConvosConfiguration(
                apiBaseURL: backendURLOverride ?? "https://api.convos-otr-dev.convos-api.xyz/api/",
                appGroupIdentifier: appGroupOverride ?? "group.org.convos.ios-preview",
                relyingPartyIdentifier: relyingPartyOverride ?? "otr-preview.convos.org",
                appCheckToken: Secrets.FIREBASE_APP_CHECK_TOKEN
            )
            return .dev(config: config)

        case "production":
            let config = ConvosConfiguration(
                apiBaseURL: backendURLOverride ?? "https://api.convos-otr-prod.convos-api.xyz/api/",
                appGroupIdentifier: appGroupOverride ?? "group.org.convos.ios",
                relyingPartyIdentifier: relyingPartyOverride ?? "convos.org",
                appCheckToken: Secrets.FIREBASE_APP_CHECK_TOKEN
            )
            return .production(config: config)

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
