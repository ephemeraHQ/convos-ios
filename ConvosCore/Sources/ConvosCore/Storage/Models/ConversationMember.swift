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

    func sortedByRole() -> [ConversationMember] {
        sorted { member1, member2 in
            // Show current user first
            if member1.isCurrentUser { return true }
            if member2.isCurrentUser { return false }

            // Sort by role hierarchy: superAdmin > admin > member
            let priority1 = member1.role.priority
            let priority2 = member2.role.priority

            if priority1 != priority2 {
                return priority1 < priority2
            }

            // Same role, sort alphabetically by name
            return member1.profile.displayName < member2.profile.displayName
        }
    }
}
