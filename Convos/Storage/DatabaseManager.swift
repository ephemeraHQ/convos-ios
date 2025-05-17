import Foundation
import GRDB

final class DatabaseManager {
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

            try db.create(table: "userProfile") { t in
                t.column("userId", .text)
                    .notNull()
                    .unique()
                    .references("user", onDelete: .cascade)
                    .primaryKey()
                t.column("name", .text).notNull()
                t.column("username", .text).notNull()
                t.column("avatar", .text)
            }

            try db.create(table: "memberProfile") { t in
                t.column("inboxId", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("username", .text).notNull()
                t.column("avatar", .text)
                t.column("isCurrentUser", .boolean).notNull().defaults(to: false)
            }

            try db.create(table: "conversation") { t in
                t.column("id", .text).primaryKey()
                t.column("isCreator", .boolean).notNull().defaults(to: false)
                t.column("kind", .text).notNull()
                t.column("consent", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("topic", .text).notNull()
                t.column("creatorId", .text).notNull()
                    .references("memberProfile", onDelete: .cascade)
                t.column("memberIds", .text).notNull()
                t.column("imageURLString", .text)
                t.column("lastMessage", .text)
            }

            try db.create(table: "member") { t in
                t.column("inboxId", .text).notNull()
                t.column("conversationId", .text)
                    .references("conversation", onDelete: .none)
                    .notNull()
                t.column("role", .text).notNull()
                t.column("consent", .text).notNull()
                t.primaryKey(["inboxId", "conversationId"])
            }

            try db.create(table: "conversationLocalState") { t in
                t.column("id", .text)
                    .references("conversation")
                    .primaryKey() // conversation.id
                t.column("isPinned", .boolean).notNull().defaults(to: false)
                t.column("isUnread", .boolean).notNull().defaults(to: false)
                t.column("isMuted", .boolean).notNull().defaults(to: false)
            }

            try db.create(table: "message") { t in
                t.column("id", .text).primaryKey()
                t.column("conversationId", .text)
                    .notNull()
                    .references("conversation", onDelete: .cascade)
                t.column("sender", .text).notNull()
                t.column("date", .datetime).notNull()
                t.column("kind", .text).notNull()
                t.column("source", .text).notNull()
                t.column("status", .text).notNull()
                t.column("sourceMessageId", .text)
            }

            try db.create(table: "messageReply") { t in
                t.column("id", .text).primaryKey()
                t.column("conversationId", .text)
                    .notNull()
                    .references("conversation", onDelete: .cascade)
                t.column("sender", .text).notNull()
                t.column("date", .datetime).notNull()
                t.column("kind", .text).notNull()
                t.column("source", .text).notNull()
                t.column("status", .text).notNull()
                t.column("sourceMessageId", .text).notNull().references("message", column: "id", onDelete: .cascade)
            }

            try db.create(table: "messageReaction") { t in
                t.column("id", .text).primaryKey()
                t.column("conversationId", .text)
                    .notNull()
                    .references("conversation", onDelete: .cascade)
                t.column("sender", .text).notNull()
                t.column("date", .datetime).notNull()
                t.column("source", .text).notNull()
                t.column("status", .text).notNull()
                t.column("sourceMessageId", .text).notNull()
                    .references("message", column: "id", onDelete: .cascade)
            }

            try db.create(table: "session") { t in
                t.column("id", .integer).primaryKey()
                t.column("currentUserId", .text)
                    .notNull()
                    .references("user", onDelete: .cascade)
            }
        }

        try migrator.migrate(dbPool)
        return dbPool
    }
}
