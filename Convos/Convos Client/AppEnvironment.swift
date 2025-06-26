import Foundation

enum AppEnvironment {
    case local, tests, dev, production

    var apiBaseURL: String {
        switch self {
        case .local, .tests: "http://localhost:4000/api/"
        case .dev: "https://api.convos-dev.convos-api.xyz/api/"
        case .production: "https://api.convos-prod.convos-api.xyz/api/"
        }
    }

    var appGroupIdentifier: String {
        switch self {
        case .local, .tests: "group.com.convos.dev"
        case .dev: "group.com.convos.preview"
        case .production: "group.com.convos.prod"
        }
    }

    var relyingPartyIdentifier: String {
        switch self {
        case .local, .tests, .dev: "preview.convos.org"
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
