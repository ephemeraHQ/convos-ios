import Foundation

// MARK: - ConversationMember

struct ConversationMember: Codable, Hashable, Identifiable {
    var id: String { profile.id }
    let profile: Profile
    let role: MemberRole
    let isCurrentUser: Bool
}

extension Array where Element == ConversationMember {
    var formattedNamesString: String {
        map { $0.profile }.formattedNamesString
    }
}
