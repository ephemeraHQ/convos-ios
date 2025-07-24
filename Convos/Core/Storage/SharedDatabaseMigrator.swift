import Foundation
import GRDB

// swiftlint:disable function_body_length

class SharedDatabaseMigrator {
    static let shared: SharedDatabaseMigrator = SharedDatabaseMigrator()

    private init() {}

    func migrate(database: any DatabaseWriter) throws {
        let migrator = createMigrator()
        try migrator.migrate(database)
    }
}

extension SharedDatabaseMigrator {
    private func createMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()

#if DEBUG
        migrator.eraseDatabaseOnSchemaChange = true
#endif

        migrator.registerMigration("createSchema") { db in
            try db.create(table: "session") { t in
                t.column("id", .integer)
                    .unique()
                    .primaryKey()
            }

            try db.create(table: "inbox") { t in
                t.column("inboxId", .text)
                    .unique()
                    .primaryKey()
                t.column("providerId", .text)
                    .notNull()
                t.column("sessionId", .integer)
                    .references("session", onDelete: .cascade)
                t.column("type", .jsonText).notNull()
                t.column("provider", .text).notNull()
            }

            try db.create(table: "member") { t in
                t.column("inboxId", .text)
                    .unique()
                    .notNull()
                    .primaryKey()
            }

            try db.create(table: "identity") { t in
                t.column("id", .text)
                    .unique()
                    .primaryKey()
                t.column("inboxId", .text)
                    .notNull()
                    .indexed()
                    .references("inbox", onDelete: .cascade)
                t.column("walletAddress", .text)
            }

            try db.create(table: "conversation") { t in
                t.column("id", .text)
                    .notNull()
                    .primaryKey()
                t.column("inboxId", .text)
                    .notNull()
                    .references("inbox", onDelete: .cascade)
                t.column("clientConversationId", .text)
                    .notNull()
                    .unique(onConflict: .replace)
                t.column("creatorId", .text)
                    .notNull()
                t.column("kind", .text).notNull()
                t.column("consent", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("name", .text)
                t.column("description", .text)
                t.column("imageURLString", .text)

                t.uniqueKey(["id", "inboxId"])
            }

            try db.create(table: "memberProfile") { t in
                t.column("inboxId", .text)
                    .notNull()
                    .unique()
                    .primaryKey()
                    .references("member", onDelete: .cascade)
                t.column("name", .text)
                t.column("avatar", .text)
            }

            try db.create(table: "invite") { t in
                t.column("id", .text)
                    .notNull()
                    .primaryKey()
                t.column("conversationId", .text)
                    .notNull()
                    .unique(onConflict: .replace)
                    .references("conversation", onDelete: .cascade)
                t.column("inviteUrlString", .text)
                    .notNull()
                t.column("maxUses", .numeric)
                t.column("usesCount", .numeric)
                    .defaults(to: 0)
                    .notNull()
                t.column("status", .text)
                    .notNull()
                t.column("createdAt", .datetime)
                    .notNull()
                t.column("inboxId", .text).notNull() // @jarodl temporary
            }

            try db.create(table: "conversation_members") { t in
                t.column("conversationId", .text)
                    .notNull()
                    .references("conversation", onDelete: .cascade)
                t.column("inboxId", .text)
                    .notNull()
                    .references("member", onDelete: .cascade)
                t.column("role", .text).notNull()
                t.column("consent", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.primaryKey(["conversationId", "inboxId"])
            }

            try db.create(table: "conversationLocalState") { t in
                t.column("conversationId", .text)
                    .notNull()
                    .unique()
                    .primaryKey()
                    .references("conversation", onDelete: .cascade)
                t.column("isPinned", .boolean).notNull().defaults(to: false)
                t.column("isUnread", .boolean).notNull().defaults(to: false)
                t.column("isUnreadUpdatedAt", .datetime)
                    .notNull()
                    .defaults(to: Date.distantPast)
                t.column("isMuted", .boolean).notNull().defaults(to: false)
            }

            try db.create(table: "message") { t in
                t.column("id", .text)
                    .notNull()
                    .primaryKey()
                    .unique(onConflict: .replace)
                t.column("clientMessageId", .text)
                    .notNull()
                    .unique(onConflict: .replace)
                t.column("conversationId", .text)
                    .notNull()
                    .references("conversation", onDelete: .cascade)
                t.column("senderId", .text)
                    .notNull()
                    .references("member", onDelete: .none)
                t.column("date", .datetime).notNull()
                t.column("status", .text).notNull()
                t.column("messageType", .text).notNull()
                t.column("contentType", .text).notNull()
                t.column("text", .text)
                t.column("emoji", .text)
                t.column("sourceMessageId", .text)
                t.column("attachmentUrls", .text)
                t.column("update", .jsonText)
            }
        }

        return migrator
    }
}

// swiftlint:enable function_body_length
