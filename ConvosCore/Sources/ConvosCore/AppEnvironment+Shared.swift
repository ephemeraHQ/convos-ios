import Foundation

// MARK: - Shared Configuration

/// Shared configuration that can be stored in Keychain
public struct SharedAppConfiguration: Codable {
    public let environment: String
    public let apiBaseURL: String
    public let appGroupIdentifier: String
    public let relyingPartyIdentifier: String
    public let xmtpEndpoint: String?

    public init(environment: AppEnvironment) {
        self.environment = environment.name
        self.apiBaseURL = environment.apiBaseURL
        self.appGroupIdentifier = environment.appGroupIdentifier
        self.relyingPartyIdentifier = environment.relyingPartyIdentifier
        self.xmtpEndpoint = environment.xmtpEndpoint
    }

    public func toAppEnvironment() -> AppEnvironment {
        let config = ConvosConfiguration(
            apiBaseURL: apiBaseURL,
            appGroupIdentifier: appGroupIdentifier,
            relyingPartyIdentifier: relyingPartyIdentifier,
            xmtpEndpoint: xmtpEndpoint,
        )

        switch environment {
        case "local":
            return .local(config: config)
        case "dev":
            return .dev(config: config)
        case "production":
            return .production(config: config)
        default:
            return .production(config: config)
        }
    }
}
