import Foundation
import GRDB

extension Database {
    func currentSession() throws -> CurrentSession? {
        guard let currentSession = try Session.fetchOne(self) else {
            return nil
        }

        let dbInboxes = try DBInbox
            .filter(Column("sessionId") == currentSession.id)
            .including(required: DBInbox.memberProfile)
            .asRequest(of: DBInboxDetails.self)
            .fetchAll(self)

        let inboxes: [Inbox] = dbInboxes.map {
            .init(
                inboxId: $0.inbox.inboxId,
                profile: $0.inboxMemberProfile.hydrateProfile()
            )
        }
        return .init(inboxes: inboxes)
    }
}
