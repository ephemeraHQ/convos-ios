import Foundation

/// Shared environment detection that works for both main app and extensions
public extension AppEnvironment {

    /// Creates an environment based on the current bundle and build configuration
    /// This can be used by both the main app and notification extension
    static func detected() -> AppEnvironment {
        // Check if we're in a test environment
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return .tests
        }
        #endif

        // Get the bundle identifier to determine environment
        let bundleId = Bundle.main.bundleIdentifier ?? ""

        // Check for notification extension
        if bundleId.contains("NotificationService") {
            // Notification extension should use the same environment as the main app
            // We'll detect this based on the app group identifier
            return detectFromAppGroup()
        }

        // For main app, use bundle identifier to determine environment
        if bundleId.contains("local") || bundleId.contains("debug") {
            return createLocalEnvironment()
        } else if bundleId.contains("dev") || bundleId.contains("preview") {
            return createDevEnvironment()
        } else {
            return createProductionEnvironment()
        }
    }

    /// Detects environment based on available app group containers
    private static func detectFromAppGroup() -> AppEnvironment {
        // Try to detect environment by checking which app group containers are available
        let appGroups = [
            "group.org.convos.ios-local",
            "group.org.convos.ios-preview",
            "group.org.convos.ios"
        ]

        for appGroup in appGroups {
            if FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) != nil {
                switch appGroup {
                case "group.org.convos.ios-local":
                    return createLocalEnvironment()
                case "group.org.convos.ios-preview":
                    return createDevEnvironment()
                case "group.org.convos.ios":
                    return createProductionEnvironment()
                default:
                    break
                }
            }
        }

        // Fallback to production if no app group is found
        return createProductionEnvironment()
    }

    /// Creates local environment configuration
    private static func createLocalEnvironment() -> AppEnvironment {
        let config = ConvosConfiguration(
            apiBaseURL: "http://localhost:4000/api/",
            appGroupIdentifier: "group.org.convos.ios-local",
            relyingPartyIdentifier: "local.convos.org",
            xmtpEndpoint: nil, // Will be set by main app if needed
            appCheckToken: "" // Will be set by main app if needed
        )
        return .local(config: config)
    }

    /// Creates dev environment configuration
    private static func createDevEnvironment() -> AppEnvironment {
        let config = ConvosConfiguration(
            apiBaseURL: "https://api.convos-otr-dev.convos-api.xyz/api/",
            appGroupIdentifier: "group.org.convos.ios-preview",
            relyingPartyIdentifier: "otr-preview.convos.org",
            xmtpEndpoint: nil,
            appCheckToken: ""
        )
        return .dev(config: config)
    }

    /// Creates production environment configuration
    private static func createProductionEnvironment() -> AppEnvironment {
        let config = ConvosConfiguration(
            apiBaseURL: "https://api.convos-otr-prod.convos-api.xyz/api/",
            appGroupIdentifier: "group.org.convos.ios",
            relyingPartyIdentifier: "convos.org",
            xmtpEndpoint: nil,
            appCheckToken: ""
        )
        return .production(config: config)
    }
}

// MARK: - Shared Configuration

/// Shared configuration that can be stored in UserDefaults or app group
public struct SharedAppConfiguration: Codable {
    public let environment: String
    public let apiBaseURL: String
    public let appGroupIdentifier: String
    public let relyingPartyIdentifier: String
    public let xmtpEndpoint: String?
    public let appCheckToken: String

    public init(environment: AppEnvironment) {
        self.environment = environment.name
        self.apiBaseURL = environment.apiBaseURL
        self.appGroupIdentifier = environment.appGroupIdentifier
        self.relyingPartyIdentifier = environment.relyingPartyIdentifier
        self.xmtpEndpoint = environment.xmtpEndpoint
        self.appCheckToken = environment.appCheckToken
    }

    public func toAppEnvironment() -> AppEnvironment {
        let config = ConvosConfiguration(
            apiBaseURL: apiBaseURL,
            appGroupIdentifier: appGroupIdentifier,
            relyingPartyIdentifier: relyingPartyIdentifier,
            xmtpEndpoint: xmtpEndpoint,
            appCheckToken: appCheckToken
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
