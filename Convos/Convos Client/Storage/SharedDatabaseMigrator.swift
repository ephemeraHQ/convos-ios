import Foundation
import GRDB

// swiftlint:disable function_body_length

class SharedDatabaseMigrator {
    static let shared: SharedDatabaseMigrator = SharedDatabaseMigrator()
    private var defaultMigrator: DatabaseMigrator

    private init() {
        defaultMigrator = DatabaseMigrator()
    }

    func migrate(database: any DatabaseWriter) throws {
#if DEBUG
        defaultMigrator.eraseDatabaseOnSchemaChange = true
#endif

        defaultMigrator.registerMigration("createUserSchema") { db in
            try db.create(table: "member") { t in
                t.column("inboxId", .text)
                    .unique()
                    .notNull()
                    .primaryKey()
            }

            try db.create(table: "user") { t in
                t.column("id", .text)
                    .unique()
                    .primaryKey()
                t.column("inboxId", .text)
                    .unique()
                    .indexed()
                    .references("member", onDelete: .none)
            }

            try db.create(table: "identity") { t in
                t.column("id", .text)
                    .unique()
                    .primaryKey()
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

            try db.create(table: "conversation") { t in
                t.column("id", .text)
                    .notNull()
                    .primaryKey()
                    .unique(onConflict: .replace)
                t.column("clientConversationId", .text)
                    .notNull()
                    .unique(onConflict: .replace)
                t.column("creatorId", .text)
                    .notNull()
                    .references("member", onDelete: .none)
                t.column("kind", .text).notNull()
                t.column("consent", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("name", .text)
                t.column("description", .text)
                t.column("imageURLString", .text)
            }

            try db.create(table: "memberProfile") { t in
                t.column("inboxId", .text)
                    .notNull()
                    .unique()
                    .primaryKey()
                t.column("name", .text).notNull()
                t.column("username", .text).notNull()
                t.column("avatar", .text)
            }

            try db.create(table: "conversation_members") { t in
                t.column("conversationId", .text)
                    .notNull()
                    .references("conversation", onDelete: .cascade)
                t.column("memberId", .text)
                    .notNull()
                    .references("member", onDelete: .cascade)
                t.column("role", .text).notNull()
                t.column("consent", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.primaryKey(["conversationId", "memberId"])
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

            try db.create(table: "session") { t in
                t.column("id", .integer)
                    .unique()
                    .primaryKey()
                t.column("userId", .text)
                    .notNull()
                    .references("user", onDelete: .cascade)
            }
        }

        try defaultMigrator.migrate(database)
    }
}

// swiftlint:enable function_body_length
