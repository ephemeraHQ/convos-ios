import Foundation
import GRDB

protocol DatabaseManagerProtocol {
    var dbWriter: DatabaseWriter { get }
    var dbReader: DatabaseReader { get }
}

final class DatabaseManager: DatabaseManagerProtocol {
    static let shared: DatabaseManager = DatabaseManager()

    let dbPool: DatabasePool

    var dbWriter: DatabaseWriter {
        dbPool as DatabaseWriter
    }

    var dbReader: DatabaseReader {
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
        let dbURL = try fileManager
            .url(for: .applicationSupportDirectory,
                 in: .userDomainMask,
                 appropriateFor: nil,
                 create: true)
            .appendingPathComponent("convos.sqlite")

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
