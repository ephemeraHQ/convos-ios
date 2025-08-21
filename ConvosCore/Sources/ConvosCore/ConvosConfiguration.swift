import Foundation

/// Configuration values passed from the host app to ConvosCore
/// 
/// This is a pure data container - all configuration values must be provided
/// by the host application. The host app is responsible for reading these
/// values from its configuration files (config.json, Secrets, etc.)
/// 
/// ConvosCore does not have any hardcoded configuration values to ensure
/// that all environments are properly configured through the host app.
public struct ConvosConfiguration {
    public let apiBaseURL: String
    public let appGroupIdentifier: String
    public let relyingPartyIdentifier: String
    public let xmtpEndpoint: String?

    public init(
        apiBaseURL: String,
        appGroupIdentifier: String,
        relyingPartyIdentifier: String,
        xmtpEndpoint: String? = nil,
    ) {
        self.apiBaseURL = apiBaseURL
        self.appGroupIdentifier = appGroupIdentifier
        self.relyingPartyIdentifier = relyingPartyIdentifier
        self.xmtpEndpoint = xmtpEndpoint
    }
}

// MARK: - Test Helpers
#if DEBUG
extension ConvosConfiguration {
    /// Test configuration - only available in DEBUG builds for unit tests
    public static var testConfig: ConvosConfiguration {
        ConvosConfiguration(
            apiBaseURL: "http://localhost:4000/api/",
            appGroupIdentifier: "group.org.convos.ios-test",
            relyingPartyIdentifier: "test.convos.org",
            xmtpEndpoint: nil,
        )
    }
}
#endif
