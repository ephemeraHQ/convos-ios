import Foundation
import GRDB

class MockDatabaseManager: DatabaseManagerProtocol {
    static let shared: MockDatabaseManager = MockDatabaseManager()
    static let previews: MockDatabaseManager = MockDatabaseManager(migrate: false)

    public let dbPool: DatabaseQueue

    public var dbWriter: DatabaseWriter {
        dbPool as DatabaseWriter
    }

    public var dbReader: DatabaseReader {
        dbPool as DatabaseReader
    }

    public func erase() throws {
        try dbPool.erase()
        try SharedDatabaseMigrator.shared.migrate(database: dbPool)
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
