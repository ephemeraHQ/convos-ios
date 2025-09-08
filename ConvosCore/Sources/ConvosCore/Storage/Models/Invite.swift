import Foundation

public struct ParsedInvite {
    public let inviteId: String
    public let inboxId: String
    public let code: String
}

public struct Invite: Codable, Hashable, Identifiable, Equatable {
    public var id: String {
        code
    }
    public let code: String
    public let conversationId: String
    public let inviteUrlString: String
    public let status: InviteStatus
    public let createdAt: Date
    public let maxUses: Int?
    public let usesCount: Int
    public let autoApprove: Bool

    public var inviteURL: URL? {
        URL(string: inviteUrlString)
    }
}

public extension Invite {
    static var empty: Self {
        .init(
            code: "",
            conversationId: "",
            inviteUrlString: "",
            status: .active,
            createdAt: .distantFuture,
            maxUses: 0,
            usesCount: 0,
            autoApprove: false
        )
    }
}
