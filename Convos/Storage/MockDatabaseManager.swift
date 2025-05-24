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
        let dbPool = try DatabasePool(path: ":memory:")
        let migrator = SharedDatabaseMigrator.shared
        try migrator.migrate(database: dbPool)
        return dbPool
    }
}
