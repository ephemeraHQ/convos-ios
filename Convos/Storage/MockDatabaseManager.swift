import Foundation
import GRDB

class MockDatabaseManager: DatabaseManagerProtocol {
    static let shared: MockDatabaseManager = MockDatabaseManager()

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
        config.prepareDatabase { db in
#if DEBUG
            db.trace { print($0) }
#endif
        }

        let dbPool = try DatabasePool(path: dbURL.path, configuration: config)
        let migrator = SharedDatabaseMigrator.shared
        try migrator.migrate(database: dbPool)
        return dbPool
    }
}
