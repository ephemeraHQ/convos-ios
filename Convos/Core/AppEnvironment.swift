import Foundation

enum AppEnvironment {
    case local, tests, dev, production

    var apiBaseURL: String {
        // Check environment variable first (highest priority)
        if !Secrets.CONVOS_API_BASE_URL.isEmpty {
            Logger.info("🌐 Using API URL from environment: \(Secrets.CONVOS_API_BASE_URL)")
            return Secrets.CONVOS_API_BASE_URL
        }

        // Then check ConfigManager
        if let configURL = ConfigManager.shared.backendURLOverride {
            Logger.info("🌐 Using API URL from ConfigManager: \(configURL)")
            return configURL
        }

        // Fall back to environment-specific defaults
        let defaultURL: String
        switch self {
        case .local, .tests:
            defaultURL = "http://localhost:4000/api/"
        case .dev:
            defaultURL = "https://api.convos-otr-dev.convos-api.xyz/api/"
        case .production:
            defaultURL = "https://api.convos-otr-prod.convos-api.xyz/api/"
        }
        Logger.info("🌐 Using default API URL for \(self): \(defaultURL)")
        return defaultURL
    }

    var appGroupIdentifier: String {
        // Check ConfigManager override
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
        // Check ConfigManager override
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

    var xmtpEndpoint: String? {
        let value = Secrets.XMTP_CUSTOM_HOST
        return value.isEmpty ? nil : value
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
