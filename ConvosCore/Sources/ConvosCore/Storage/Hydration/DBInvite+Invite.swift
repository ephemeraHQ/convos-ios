import Foundation

extension DBInvite {
    func hydrateInvite() -> Invite {
        // TODO: We can extract additional metadata from the urlSlug
        .init(
            conversationId: conversationId,
            urlSlug: urlSlug,
            expiresAt: nil,
            maxUses: nil,
            usesCount: 0
        )
    }
}
