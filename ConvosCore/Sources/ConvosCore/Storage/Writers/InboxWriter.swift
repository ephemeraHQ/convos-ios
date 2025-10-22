import Foundation
import GRDB

/// Writes inbox data to the database
struct InboxWriter {
    private let dbWriter: any DatabaseWriter

    init(dbWriter: any DatabaseWriter) {
        self.dbWriter = dbWriter
    }

    @discardableResult
    func save(inboxId: String, clientId: String) async throws -> DBInbox {
        try await dbWriter.write { db in
            // Check if inbox already exists
            if let existingInbox = try DBInbox.fetchOne(db, id: inboxId) {
                return existingInbox
            }

            let inbox = DBInbox(
                inboxId: inboxId,
                clientId: clientId,
                createdAt: Date()
            )
            try inbox.insert(db)
            return inbox
        }
    }

    func delete(inboxId: String) async throws {
        try await dbWriter.write { db in
            _ = try DBInbox.deleteOne(db, id: inboxId)
        }
    }

    func delete(clientId: String) async throws {
        try await dbWriter.write { db in
            try DBInbox
                .filter(DBInbox.Columns.clientId == clientId)
                .deleteAll(db)
        }
    }

    func deleteAll() async throws {
        _ = try await dbWriter.write { db in
            try DBInbox.deleteAll(db)
        }
    }
}
