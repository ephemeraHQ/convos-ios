import Foundation

extension DBInboxDetails {
    func hydrateInbox() -> Inbox {
        .init(inboxId: inbox.inboxId,
              profile: inboxMemberProfile.hydrateProfile()
        )
    }
}
