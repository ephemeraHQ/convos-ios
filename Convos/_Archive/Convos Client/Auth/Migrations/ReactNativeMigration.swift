import Foundation

protocol ConvosMigration {
    var needsMigration: Bool { get }
    func performMigration(for userIdentifier: String) throws
}

class ReactNativeMigration: ConvosMigration {
    enum ReactNativeMigrationError: Error {
        case databaseKeyNotFound,
             failedDecodingDatabaseKey,
             attemptingToPerformUnnecessaryMigration
    }

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
            throw ReactNativeMigrationError.attemptingToPerformUnnecessaryMigration
        }

        let reactNativeSharedDefaultsDatabaseKey = "\(reactNativeSharedDatabaseKeyPrefix)\(userIdentifier)"
        guard let retrievedDatabaseKeyString = defaults.string(
            forKey: reactNativeSharedDefaultsDatabaseKey
        ) else {
            throw ReactNativeMigrationError.databaseKeyNotFound
        }
        guard let retrievedDatabaseKey = Data(base64Encoded: retrievedDatabaseKeyString) else {
            throw ReactNativeMigrationError.failedDecodingDatabaseKey
        }
        _ = try TurnkeyDatabaseKeyStore.shared.saveDatabaseKey(retrievedDatabaseKey, for: userIdentifier)

        defaults.removeObject(forKey: reactNativeSharedDefaultsDatabaseKey)

        performed = true
    }
}
