import Foundation

enum AppEnvironment {
    case local, dev, production

    var appGroupIdentifier: String {
        switch self {
        case .local: "group.com.convos.dev"
        case .dev: "group.com.convos.preview"
        case .production: "group.com.convos.prod"
        }
    }

    var relyingPartyIdentifier: String {
        switch self {
        case .local, .dev: "preview.convos.org"
        case .production: "convos.org"
        }
    }

    var defaultDatabasesDirectoryURL: URL {
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
        guard let groupUrl = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            fatalError("Failed getting container URL for group identifier: \(appGroupIdentifier)")
        }
        return groupUrl
    }
}
