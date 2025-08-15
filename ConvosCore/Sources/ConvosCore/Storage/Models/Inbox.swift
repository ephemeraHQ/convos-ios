import Foundation

extension Inbox {
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

struct Inbox: Codable, Identifiable, Hashable {
    var id: String { inboxId }
    let inboxId: String
    let identities: [Identity]
    let profile: Profile
    let type: InboxType
    let provider: InboxProvider
    let providerId: String
}

enum InboxType: String, Codable {
    case standard, ephemeral
}

enum InboxProvider: Codable, Hashable {
    case local, external(InboxExternalProvider)
}

enum InboxExternalProvider: String, Codable {
    case turnkey, passkey
}
