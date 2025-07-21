import Foundation

enum AppEnvironment {
    case local, tests, dev, otrDev, production

    var apiBaseURL: String {
        switch self {
        case .local, .tests: "http://localhost:4000/api/"
        case .dev: "https://api.convos-dev.convos-api.xyz/api/"
        case .otrDev: "https://api.convos-otr-dev.convos-api.xyz/api/"
        case .production: "https://api.convos-prod.convos-api.xyz/api/"
        }
    }

    var passkeyApiBaseURL: String {
        "https://passkey-auth-backend.vercel.app/api"
    }

    var appGroupIdentifier: String {
        switch self {
        case .local, .tests, .dev, .otrDev:
            "group.com.convos.preview"
        case .production: "group.com.convos.prod"
        }
    }

    var relyingPartyIdentifier: String {
        switch self {
        case .local, .tests, .dev: "preview.convos.org"
        case .otrDev: "otr-preview.convos.org"
        case .production: "convos.org"
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
        return defaultDatabasesDirectoryURL.path
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
