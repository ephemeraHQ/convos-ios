import Foundation

public enum ApnsEnvironment: String, Codable {
    case sandbox
    case production
}

public enum AppEnvironment {
    case local(config: ConvosConfiguration)
    case tests
    case dev(config: ConvosConfiguration)
    case production(config: ConvosConfiguration)

    public var name: String {
        switch self {
            case .local:
            return "local"
        case .dev:
            return "dev"
        case .production:
            return "production"
        case .tests:
            return "tests"
        }
    }

    /// Create an environment with custom configuration
    public static func configured(_ config: ConvosConfiguration, type: EnvironmentType) -> AppEnvironment {
        switch type {
        case .local:
            return .local(config: config)
        case .dev:
            return .dev(config: config)
        case .production:
            return .production(config: config)
        case .tests:
            return .tests
        }
    }

    public enum EnvironmentType {
        case local, dev, production, tests
    }

    var appCheckToken: String {
        switch self {
        case .local(config: let config), .dev(config: let config), .production(config: let config):
            return config.appCheckToken
        case .tests:
            return "test-token"
        }
    }

    var apiBaseURL: String {
        switch self {
        case .local(let config):
            Logger.info("🌐 Using API URL from local config: \(config.apiBaseURL)")
            return config.apiBaseURL
        case .tests:
            return "http://localhost:4000/api/"
        case .dev(let config):
            Logger.info("🌐 Using API URL from dev config: \(config.apiBaseURL)")
            return config.apiBaseURL
        case .production(let config):
            Logger.info("🌐 Using API URL from production config: \(config.apiBaseURL)")
            return config.apiBaseURL
        }
    }

    public var appGroupIdentifier: String {
        switch self {
        case .local(let config):
            return config.appGroupIdentifier
        case .tests:
            return "group.org.convos.ios-local"
        case .dev(let config):
            return config.appGroupIdentifier
        case .production(let config):
            return config.appGroupIdentifier
        }
    }

    public var relyingPartyIdentifier: String {
        switch self {
        case .local(let config):
            return config.relyingPartyIdentifier
        case .tests:
            return "local.convos.org"
        case .dev(let config):
            return config.relyingPartyIdentifier
        case .production(let config):
            return config.relyingPartyIdentifier
        }
    }

    var xmtpEndpoint: String? {
        switch self {
        case .local(let config):
            return config.xmtpEndpoint
        case .tests:
            return nil
        case .dev(let config):
            return config.xmtpEndpoint
        case .production(let config):
            return config.xmtpEndpoint
        }
    }

    var apnsEnvironment: ApnsEnvironment {
        // Check if this is a debug build (built locally with Xcode)
        #if DEBUG
        return .sandbox
        #else
        // Release builds (distributed via TestFlight/App Store) use production
        return .production
        #endif
    }

    private var isTestingEnvironment: Bool {
        switch self {
        case .tests:
            true
        default:
            false
        }
    }

    var defaultDatabasesDirectoryURL: URL {
        guard !isTestingEnvironment else {
            return FileManager.default.temporaryDirectory
        }

        guard let groupUrl = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            fatalError("Failed getting container URL for group identifier: \(appGroupIdentifier)")
        }
        return groupUrl
    }

    var defaultDatabasesDirectory: String {
        defaultDatabasesDirectoryURL.path
    }

    var reactNativeDatabaseDirectory: URL {
        guard !isTestingEnvironment else {
            return FileManager.default.temporaryDirectory
        }

        guard let groupUrl = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            fatalError("Failed getting container URL for group identifier: \(appGroupIdentifier)")
        }
        return groupUrl
    }
}
