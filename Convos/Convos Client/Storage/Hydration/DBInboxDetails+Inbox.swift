import Foundation

extension DBInboxDetails {
    func hydrateInbox() -> Inbox {
        .init(inboxId: inbox.inboxId,
              identities: inboxIdentities,
              profile: inboxMemberProfile.hydrateProfile()
        )
    }
}
