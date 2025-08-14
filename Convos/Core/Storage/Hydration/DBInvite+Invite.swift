import Foundation

extension DBInvite {
    func hydrateInvite() -> Invite {
        .init(
            code: id,
            conversationId: conversationId,
            inviteUrlString: inviteUrlString,
            status: status,
            createdAt: createdAt,
            maxUses: maxUses,
            usesCount: usesCount,
            autoApprove: autoApprove
        )
    }
}
