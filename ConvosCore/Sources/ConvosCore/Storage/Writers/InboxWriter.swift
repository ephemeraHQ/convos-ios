import Foundation
import GRDB

public protocol InboxWriterProtocol {
    func storeInbox(inboxId: String) async throws
    func deleteInbox(inboxId: String) async throws
}

final class InboxWriter: InboxWriterProtocol {
    private let databaseWriter: any DatabaseWriter

    init(databaseWriter: any DatabaseWriter) {
        self.databaseWriter = databaseWriter
    }

    func storeInbox(inboxId: String) async throws {
        let member: Member = .init(inboxId: inboxId)
        let memberProfile: MemberProfile = .init(inboxId: inboxId,
                                                 name: nil,
                                                 avatar: nil)
        let dbInbox = DBInbox(inboxId: inboxId)
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
            // this will cascade delete:
            //    - conversations (due to FK constraint)
            //    - conversation_members (due to conversation FK cascade)
            //    - conversationLocalState (due to conversation FK cascade)
            //    - messages (due to conversation FK cascade)
            //    - invites (due to conversation_members FK cascade)
            guard let inbox = try DBInbox.fetchOne(db, key: inboxId) else {
                Logger.error("Inbox not found, skipping delete")
                return
            }
            try inbox.delete(db)

            // this will cascade delete:
            //    - memberProfile (due to member FK cascade)
            // Note: member table doesn't have FK to inbox, so we need to delete manually
            if let member = try Member.fetchOne(db, key: inboxId) {
                try member.delete(db)
            } else {
                Logger.error("Member not found, skipping delete")
            }
        }
    }
}
