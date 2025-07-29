import Foundation

enum AppEnvironment {
    case local, tests, dev, production

    var apiBaseURL: String {
        // Check environment variable first (highest priority)
        if !Secrets.CONVOS_API_BASE_URL.isEmpty {
            return Secrets.CONVOS_API_BASE_URL
        }

        // Then check ConfigManager
        if let configURL = ConfigManager.shared.backendURLOverride {
            return configURL
        }

        // Fall back to environment-specific defaults
        switch self {
        case .local, .tests:
            return "http://localhost:4000/api/"
        case .dev:
            return "https://api.convos-otr-dev.convos-api.xyz/api/"
        case .production:
            return "https://api.convos-otr-prod.convos-api.xyz/api/"
        }
    }

    var appGroupIdentifier: String {
        // Check environment variable first (highest priority)
        if let envValue = getEnvironmentVariable("APP_GROUP_IDENTIFIER"), !envValue.isEmpty {
            return envValue
        }

        // Then check ConfigManager
        if let configGroupId = ConfigManager.shared.appGroupOverride {
            return configGroupId
        }

        // Fall back to environment-specific defaults
        switch self {
        case .local: return "group.org.convos.ios-local"
        case .tests, .dev: return "group.org.convos.ios-preview"
        case .production: return "group.org.convos.ios"
        }
    }

    var relyingPartyIdentifier: String {
        // Check environment variable first (highest priority)
        if let envValue = getEnvironmentVariable("RELYING_PARTY_IDENTIFIER"), !envValue.isEmpty {
            return envValue
        }

        // Then check ConfigManager
        if let configRpId = ConfigManager.shared.relyingPartyOverride {
            return configRpId
        }

        // Fall back to environment-specific defaults
        switch self {
        case .local, .tests: return "local.convos.org"
        case .dev: return "otr-preview.convos.org"
        case .production: return "convos.org"
        }
    }

    var defaultDatabasesDirectoryURL: URL {
        guard self != .tests else {
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
        guard self != .tests else {
            return FileManager.default.temporaryDirectory
        }

        guard let groupUrl = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            fatalError("Failed getting container URL for group identifier: \(appGroupIdentifier)")
        }
        return groupUrl
    }

    /// Helper function to get environment variables from Secrets using reflection
    private func getEnvironmentVariable(_ key: String) -> String? {
        let mirror = Mirror(reflecting: Secrets.self)
        for child in mirror.children {
            if child.label == key {
                return child.value as? String
            }
        }
        return nil
    }
}
