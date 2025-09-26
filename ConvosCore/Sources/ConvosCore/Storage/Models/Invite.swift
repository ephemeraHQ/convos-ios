import Foundation

public struct Invite: Codable, Hashable, Identifiable, Equatable {
    public var id: String {
        code
    }
    public let code: String
    public let conversationId: String
    public let inviteSlug: String
    public let createdAt: Date
    public let expiresAt: Date?
    public let maxUses: Int?
    public let usesCount: Int
}

public extension Invite {
    static var empty: Self {
        .init(
            code: "",
            conversationId: "",
            inviteSlug: "",
            createdAt: .distantFuture,
            expiresAt: nil,
            maxUses: nil,
            usesCount: 0,
        )
    }
}
