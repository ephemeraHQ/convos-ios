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
                profile: $0.inboxMemberProfile.hydrateProfile(),
                type: $0.inbox.type,
                provider: $0.inbox.provider,
                providerId: $0.inbox.providerId
            )
        }
        return .init(inboxes: inboxes)
    }
}
