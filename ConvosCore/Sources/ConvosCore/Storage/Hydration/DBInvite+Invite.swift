import Foundation

extension DBInvite {
    func hydrateInvite() -> Invite {
        .init(
            code: code,
            conversationId: conversationId,
            inviteSlug: inviteSlug,
            createdAt: createdAt,
            expiresAt: expiresAt,
            maxUses: maxUses,
            usesCount: usesCount,
        )
    }
}
