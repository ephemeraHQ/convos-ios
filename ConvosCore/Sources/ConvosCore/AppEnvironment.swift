import Foundation

public enum ApnsEnvironment: String, Codable {
    case sandbox
    case production
}

public enum BuildEnvironment {
    case simulator
    case development
    case distribution
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

    public var firebaseConfigURL: URL? {
        let resource: String
        switch self {
        case .local, .tests:
            resource = "GoogleService-Info.Local"
        case .dev:
            resource = "GoogleService-Info.Dev"
        case .production:
            resource = "GoogleService-Info.Prod"
        }

        if let url = Bundle.main.url(forResource: resource, withExtension: "plist") {
            return url
        }

        return nil
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
        case .local(config: let config), .dev(config: let config), .production(config: let config):
            return config.appGroupIdentifier
        case .tests:
            return "group.org.convos.ios-local"
        }
    }

    public var keychainAccessGroup: String {
        // Use the app group identifier with team prefix for keychain sharing
        // This matches $(AppIdentifierPrefix)$(APP_GROUP_IDENTIFIER) in entitlements
        let teamPrefix = "FY4NZR34Z3."
        return teamPrefix + appGroupIdentifier
    }

    public var relyingPartyIdentifier: String {
        switch self {
        case .local(config: let config), .dev(config: let config), .production(config: let config):
            return config.relyingPartyIdentifier
        case .tests:
            return "local.convos.org"
        }
    }

    var xmtpEndpoint: String? {
        switch self {
        case .local(config: let config), .dev(config: let config), .production(config: let config):
            return config.xmtpEndpoint
        case .tests:
            return nil
        }
    }

    public var apnsEnvironment: ApnsEnvironment {
        switch buildEnvironment {
        case .simulator:
            Logger.info("Simulator build detected - using sandbox APNS")
            return .sandbox
        case .development:
            Logger.info("Development build detected (has embedded.mobileprovision) - using sandbox APNS")
            return .sandbox
        case .distribution:
            Logger.info("Distribution build detected (TestFlight/App Store) - using production APNS")
            return .production
        }
    }

    public var buildEnvironment: BuildEnvironment {
        if isSimulator() {
            return .simulator
        } else if hasEmbeddedMobileProvision() {
            return .development
        } else {
            return .distribution
        }
    }

    public func isSimulator() -> Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    public func hasEmbeddedMobileProvision() -> Bool {
        Bundle.main.path(forResource: "embedded", ofType: "mobileprovision") != nil
    }
}

public extension AppEnvironment {
    private var isTestingEnvironment: Bool {
        switch self {
        case .tests:
            true
        default:
            false
        }
    }

    var isProduction: Bool {
        switch self {
        case .production:
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
