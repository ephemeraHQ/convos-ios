import Foundation

/// Configuration values passed from the host app to ConvosCore
public struct ConvosConfiguration {
    public let apiBaseURL: String
    public let appGroupIdentifier: String
    public let relyingPartyIdentifier: String
    public let xmtpEndpoint: String?
    public let appCheckToken: String

    public init(
        apiBaseURL: String,
        appGroupIdentifier: String,
        relyingPartyIdentifier: String,
        xmtpEndpoint: String? = nil,
        appCheckToken: String,
    ) {
        self.apiBaseURL = apiBaseURL
        self.appGroupIdentifier = appGroupIdentifier
        self.relyingPartyIdentifier = relyingPartyIdentifier
        self.xmtpEndpoint = xmtpEndpoint
        self.appCheckToken = appCheckToken
    }

    /// Convenience initializer for common environments
    public static func local(
        apiBaseURL: String = "http://localhost:4000/api/",
        appGroupIdentifier: String = "group.org.convos.ios-local",
        relyingPartyIdentifier: String = "local.convos.org",
        xmtpEndpoint: String? = nil,
        appCheckToken: String,
    ) -> ConvosConfiguration {
        ConvosConfiguration(
            apiBaseURL: apiBaseURL,
            appGroupIdentifier: appGroupIdentifier,
            relyingPartyIdentifier: relyingPartyIdentifier,
            xmtpEndpoint: xmtpEndpoint,
            appCheckToken: appCheckToken
        )
    }

    public static func dev(
        apiBaseURL: String = "https://api.convos-otr-dev.convos-api.xyz/api/",
        appGroupIdentifier: String = "group.org.convos.ios-preview",
        relyingPartyIdentifier: String = "otr-preview.convos.org",
        xmtpEndpoint: String? = nil,
        appCheckToken: String,
    ) -> ConvosConfiguration {
        ConvosConfiguration(
            apiBaseURL: apiBaseURL,
            appGroupIdentifier: appGroupIdentifier,
            relyingPartyIdentifier: relyingPartyIdentifier,
            xmtpEndpoint: xmtpEndpoint,
            appCheckToken: appCheckToken
        )
    }

    public static func production(
        apiBaseURL: String = "https://api.convos-otr-prod.convos-api.xyz/api/",
        appGroupIdentifier: String = "group.org.convos.ios",
        relyingPartyIdentifier: String = "convos.org",
        xmtpEndpoint: String? = nil,
        appCheckToken: String
    ) -> ConvosConfiguration {
        ConvosConfiguration(
            apiBaseURL: apiBaseURL,
            appGroupIdentifier: appGroupIdentifier,
            relyingPartyIdentifier: relyingPartyIdentifier,
            xmtpEndpoint: xmtpEndpoint,
            appCheckToken: appCheckToken
        )
    }
}
