import Foundation

public extension Inbox {
    static func mock() -> Self {
        .init(
            inboxId: UUID().uuidString,
            profile: .mock()
        )
    }
}

public struct Inbox: Codable, Identifiable, Hashable {
    public var id: String { inboxId }
    public let inboxId: String
    public let profile: Profile
}
