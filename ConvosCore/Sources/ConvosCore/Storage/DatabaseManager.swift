import Foundation
import GRDB

public protocol DatabaseManagerProtocol {
    var dbWriter: DatabaseWriter { get }
    var dbReader: DatabaseReader { get }
}

public final class DatabaseManager: DatabaseManagerProtocol {
    let environment: AppEnvironment

    public let dbPool: DatabasePool

    public var dbWriter: DatabaseWriter {
        dbPool as DatabaseWriter
    }

    public var dbReader: DatabaseReader {
        dbPool as DatabaseReader
    }

    init(environment: AppEnvironment) {
        self.environment = environment
        do {
            dbPool = try Self.makeDatabasePool(environment: environment)
        } catch {
            fatalError("Failed to initialize database: \(error)")
        }
    }

    private static func makeDatabasePool(environment: AppEnvironment) throws -> DatabasePool {
        let fileManager = FileManager.default
        // Use the shared App Group container so the main app and NSE share the same DB
        let groupDirURL = environment.defaultDatabasesDirectoryURL
        let dbURL = groupDirURL.appendingPathComponent("convos.sqlite")

        // Ensure the App Group directory exists
        try fileManager.createDirectory(at: groupDirURL, withIntermediateDirectories: true)

        // Migrate legacy DB from Application Support → App Group on first run (if needed)
        let legacyURL = try fileManager
            .url(for: .applicationSupportDirectory,
                 in: .userDomainMask,
                 appropriateFor: nil,
                 create: true)
            .appendingPathComponent("convos.sqlite")
        if !fileManager.fileExists(atPath: dbURL.path), fileManager.fileExists(atPath: legacyURL.path) {
            try fileManager.copyItem(at: legacyURL, to: dbURL)
        }

        var config = Configuration()
        // Add process identifier to help with debugging concurrent access issues
        let isNSE = Bundle.main.bundleIdentifier?.contains("NotificationService") ?? false
        config.label = isNSE ? "ConvosDB-NSE" : "ConvosDB-MainApp"
        config.foreignKeysEnabled = true
        // Improve concurrent access handling for multi-process scenarios (NSE + Main App)
        config.maximumReaderCount = 5  // Allow multiple readers
        config.busyMode = .timeout(10.0)  // Wait up to 10 seconds for locks
#if DEBUG
//        config.prepareDatabase { db in
//            db.trace { Logger.info("\($0)") }
//        }
#endif

        let dbPool = try DatabasePool(path: dbURL.path, configuration: config)
        let migrator = SharedDatabaseMigrator.shared
        try migrator.migrate(database: dbPool)
        return dbPool
    }
}
