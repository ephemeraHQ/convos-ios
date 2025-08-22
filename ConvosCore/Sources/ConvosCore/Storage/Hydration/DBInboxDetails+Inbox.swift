import Foundation

extension DBInboxDetails {
    func hydrateInbox() -> Inbox {
        .init(inboxId: inbox.inboxId,
              profile: inboxMemberProfile.hydrateProfile(),
              type: inbox.type,
              provider: inbox.provider,
              providerId: inbox.providerId
        )
    }
}
