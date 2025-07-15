import Foundation
import GRDB

class MockDatabaseManager: DatabaseManagerProtocol {
    static let shared: MockDatabaseManager = MockDatabaseManager()
    static let previews: MockDatabaseManager = MockDatabaseManager(migrate: false)

    let dbPool: DatabaseQueue

    var dbWriter: DatabaseWriter {
        dbPool as DatabaseWriter
    }

    var dbReader: DatabaseReader {
        dbPool as DatabaseReader
    }

    private init(migrate: Bool = true) {
        do {
            dbPool = try DatabaseQueue(named: "MockDatabase")
            if migrate {
                try SharedDatabaseMigrator.shared.migrate(database: dbPool)
            }
        } catch {
            fatalError("Failed to initialize database: \(error)")
        }
    }
}
