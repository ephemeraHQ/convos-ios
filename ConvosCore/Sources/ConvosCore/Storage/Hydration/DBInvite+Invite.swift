import Foundation

extension DBInvite {
    func hydrateInvite() -> Invite {
        // @jarodl We can extract additional metadata from the urlSlug
        .init(
            conversationId: conversationId,
            urlSlug: urlSlug,
            expiresAt: expiresAt,
            maxUses: nil
        )
    }
}
