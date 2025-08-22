import Foundation
import GRDB

public protocol InboxWriterProtocol {
    func storeInbox(inboxId: String,
                    type: InboxType,
                    provider: InboxProvider,
                    providerId: String) async throws
    func deleteInbox(inboxId: String) async throws
}

final class InboxWriter: InboxWriterProtocol {
    private let databaseWriter: any DatabaseWriter

    init(databaseWriter: any DatabaseWriter) {
        self.databaseWriter = databaseWriter
    }

    func storeInbox(inboxId: String,
                    type: InboxType,
                    provider: InboxProvider,
                    providerId: String) async throws {
        let member: Member = .init(inboxId: inboxId)
        let memberProfile: MemberProfile = .init(inboxId: inboxId,
                                                 name: nil,
                                                 avatar: nil)
        let dbInbox = DBInbox(
            inboxId: inboxId,
            type: type,
            provider: provider,
            providerId: providerId
        )
        try await databaseWriter.write { db in
            let session = Session()
            try? session.save(db)

            try dbInbox.save(db)
            try member.save(db)
            try? memberProfile.insert(db)
        }
    }

    func deleteInbox(inboxId: String) async throws {
        try await databaseWriter.write { db in
            guard let inbox = try DBInbox.fetchOne(db, id: inboxId) else {
                Logger.error("Inbox not found, skipping delete")
                return
            }
            let conversations = DBConversation.filter(DBConversation.Columns.inboxId == inboxId)
            try inbox.delete(db)
            try conversations.deleteAll(db)
        }
    }
}
