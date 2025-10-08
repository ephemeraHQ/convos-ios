import Foundation
import GRDB

/// Repository for fetching inbox data from the database
public struct InboxesRepository {
    private let databaseReader: any DatabaseReader

    public init(databaseReader: any DatabaseReader) {
        self.databaseReader = databaseReader
    }

    /// Fetch all inboxes from the database
    public func allInboxes() throws -> [Inbox] {
        try databaseReader.read { db in
            try DBInbox
                .fetchAll(db)
                .map { $0.toDomain() }
        }
    }

    /// Fetch a specific inbox by inboxId
    public func inbox(for inboxId: String) throws -> Inbox? {
        try databaseReader.read { db in
            try DBInbox
                .fetchOne(db, id: inboxId)?
                .toDomain()
        }
    }

    /// Fetch inbox by clientId
    public func inbox(byClientId clientId: String) throws -> Inbox? {
        try databaseReader.read { db in
            try DBInbox
                .filter(DBInbox.Columns.clientId == clientId)
                .fetchOne(db)?
                .toDomain()
        }
    }
}
