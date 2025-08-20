import Foundation

public extension Inbox {
    static func mock(type: InboxType = .standard) -> Self {
        .init(
            inboxId: UUID().uuidString,
            identities: [],
            profile: .mock(),
            type: type,
            provider: .external(.turnkey),
            providerId: UUID().uuidString
        )
    }
}

public struct Inbox: Codable, Identifiable, Hashable {
    public var id: String { inboxId }
    public let inboxId: String
    public let identities: [Identity]
    public let profile: Profile
    public let type: InboxType
    public let provider: InboxProvider
    public let providerId: String
}

public enum InboxType: String, Codable {
    case standard, ephemeral
}

public enum InboxProvider: Codable, Hashable {
    case local, external(InboxExternalProvider)
}

public enum InboxExternalProvider: String, Codable {
    case turnkey, passkey
}
