import Foundation

enum AppEnvironment {
    case local, tests, dev, production

    var apiBaseURL: String {
        // Check ConfigManager override first
        if let configURL = ConfigManager.shared.backendURLOverride {
            return configURL
        }

        // Fall back to environment-specific defaults
        switch self {
        case .local, .tests:
            return Secrets.CONVOS_API_BASE_URL.isEmpty ?
                "http://localhost:4000/api/" : Secrets.CONVOS_API_BASE_URL
        case .dev:
            return "https://api.convos-otr-dev.convos-api.xyz/api/"
        case .production:
            return "https://api.convos-otr-prod.convos-api.xyz/api/"
        }
    }

    var appGroupIdentifier: String {
        // Check ConfigManager override first
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
        // Check ConfigManager override first
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
}
