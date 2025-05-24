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
            fatalError("Failed to initialize mock database: \(error)")
        }
    }

    private static func makeDatabasePool() throws -> DatabasePool {
        let dbPool = try DatabasePool(path: ":memory:")
        let migrator = SharedDatabaseMigrator.shared
        try migrator.migrate(database: dbPool)
        return dbPool
    }
}
