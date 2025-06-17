import Foundation

protocol ConvosMigration {
    var needsMigration: Bool { get }
    func performMigration(for userIdentifier: String) throws
}

class ReactNativeMigration: ConvosMigration {
    private let environment: AppEnvironment
    private var performed: Bool = false
    private let reactNativeSharedDatabaseKeyPrefix: String = "SHARED_DEFAULTS_XMTP_KEY_"
    private let defaults: UserDefaults = .standard

    var needsMigration: Bool {
        guard !performed else {
            return false
        }
        return defaults
            .dictionaryRepresentation()
            .keys
            .contains(
                where: { $0.hasPrefix(reactNativeSharedDatabaseKeyPrefix) }
            )
    }

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    func performMigration(for userIdentifier: String) throws {
        guard needsMigration else {
            return
        }

        let reactNativeSharedDefaultsDatabaseKey = "\(reactNativeSharedDatabaseKeyPrefix)\(userIdentifier)"
        guard let retrievedDatabaseKeyString = defaults.string(
            forKey: reactNativeSharedDefaultsDatabaseKey
        ) else {
            Logger.error("Attempted to perform migration, database key not found")
            return
        }
        guard let retrievedDatabaseKey = Data(base64Encoded: retrievedDatabaseKeyString) else {
            Logger.error("Failed decoding database key to base64")
            return
        }
        _ = try TurnkeyDatabaseKeyStore.shared.saveDatabaseKey(retrievedDatabaseKey, for: userIdentifier)

        defaults.removeObject(forKey: reactNativeSharedDefaultsDatabaseKey)

        performed = true
    }
}
