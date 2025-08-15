import Foundation

struct ParsedInvite {
    let inviteId: String
    let inboxId: String
    let code: String
}

struct Invite: Codable, Hashable, Identifiable, Equatable {
    var id: String {
        code
    }
    let code: String
    let conversationId: String
    let inviteUrlString: String
    let status: InviteStatus
    let createdAt: Date
    let maxUses: Int?
    let usesCount: Int
    let autoApprove: Bool
}
