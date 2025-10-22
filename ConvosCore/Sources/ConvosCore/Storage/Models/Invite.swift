import Foundation

public struct Invite: Codable, Hashable, Identifiable, Equatable {
    public var id: String {
        urlSlug
    }
    public let conversationId: String
    public let urlSlug: String
    public let expiresAt: Date?
    public let expiresAfterUse: Bool
}

public extension Invite {
    static var empty: Self {
        .init(
            conversationId: "",
            urlSlug: "",
            expiresAt: nil,
            expiresAfterUse: false
        )
    }

    var isEmpty: Bool {
        urlSlug.isEmpty
    }
}
