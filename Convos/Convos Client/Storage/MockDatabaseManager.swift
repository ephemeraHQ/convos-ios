import Foundation
import GRDB

class MockDatabaseManager: DatabaseManagerProtocol {
    static let shared: MockDatabaseManager = MockDatabaseManager()

    let dbPool: DatabaseQueue

    var dbWriter: DatabaseWriter {
        dbPool as DatabaseWriter
    }

    var dbReader: DatabaseReader {
        dbPool as DatabaseReader
    }

    private init() {
        do {
            dbPool = try DatabaseQueue(named: "MockDatabase")
            try SharedDatabaseMigrator.shared.migrate(database: dbPool)
        } catch {
            fatalError("Failed to initialize database: \(error)")
        }
    }
}
