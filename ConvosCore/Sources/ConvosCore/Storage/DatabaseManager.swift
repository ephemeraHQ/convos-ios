import Foundation
import GRDB

public protocol DatabaseManagerProtocol {
    var dbWriter: DatabaseWriter { get }
    var dbReader: DatabaseReader { get }
}

public final class DatabaseManager: DatabaseManagerProtocol {
    public static let shared: DatabaseManager = DatabaseManager()

    public let dbPool: DatabasePool

    public var dbWriter: DatabaseWriter {
        dbPool as DatabaseWriter
    }

    public var dbReader: DatabaseReader {
        dbPool as DatabaseReader
    }

    private init() {
        do {
            dbPool = try Self.makeDatabasePool()
        } catch {
            fatalError("Failed to initialize database: \(error)")
        }
    }

    private static func makeDatabasePool() throws -> DatabasePool {
        let fileManager = FileManager.default
        // Use the shared App Group container so the main app and NSE share the same DB
        let environment = AppEnvironment.detected()
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
        config.label = "ConvosDB"
        config.foreignKeysEnabled = true
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
