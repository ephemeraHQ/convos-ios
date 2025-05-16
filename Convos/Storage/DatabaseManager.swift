import Foundation
import GRDB

final class DatabaseManager {
    static let shared = DatabaseManager()

    let dbPool: DatabasePool

    private init() {
        do {
            dbPool = try DatabaseManager.makeDatabasePool()
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

        let dbPool = try DatabasePool(path: dbURL.path, configuration: config)
        var migrator = DatabaseMigrator()

#if DEBUG
        migrator.eraseDatabaseOnSchemaChange = true
#endif

        migrator.registerMigration("createUserSchema") { db in
            try db.create(table: "user") { t in
                t.column("id", .text).primaryKey()
            }

            try db.create(table: "identity") { t in
                t.column("id", .text).primaryKey()
                t.column("userId", .text)
                    .notNull()
                    .indexed()
                    .references("user", onDelete: .cascade)
                t.column("walletAddress", .text).notNull()
                t.column("xmtpId", .text)
            }

            try db.create(table: "profile") { t in
                t.column("id", .text).primaryKey()
                t.column("userId", .text)
                    .notNull()
                    .unique()
                    .references("user", onDelete: .cascade)
                t.column("name", .text).notNull()
                t.column("username", .text).notNull()
                t.column("avatar", .text)
            }
            
            try db.create(table: "session") { t in
                t.column("id", .integer).primaryKey()
                t.column("currentUserId", .text).notNull()
                    .references("user", onDelete: .cascade)
            }
        }

        try migrator.migrate(dbPool)
        return dbPool
    }
}
