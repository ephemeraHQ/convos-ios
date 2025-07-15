import Foundation
import GRDB

struct MemberProfile: Codable, FetchableRecord, PersistableRecord, Hashable {
    let inboxId: String
    let name: String
    let username: String
    let avatar: String?

    static let memberForeignKey: ForeignKey = ForeignKey(["inboxId"], to: ["inboxId"])

    static let member: BelongsToAssociation<MemberProfile, Member> = belongsTo(
        Member.self,
        using: memberForeignKey
    )
}

struct Profile: Codable, Identifiable, Hashable {
    let id: String // @jarodl change to inboxId for clarity
    let name: String
    let username: String
    let avatar: String?

    var avatarURL: URL? {
        guard let avatar, let url = URL(string: avatar) else {
            return nil
        }
        return url
    }

    var displayName: String {
        name.isEmpty ? username : name
    }

    static var empty: Profile {
        .init(
            id: UUID().uuidString,
            name: "",
            username: "",
            avatar: nil
        )
    }

    init(id: String,
         name: String,
         username: String,
         avatar: String?) {
        self.id = id
        self.name = name
        self.username = username
        self.avatar = avatar
    }
}

// MARK: - Array Extensions

extension Array where Element == ConversationMember {
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

extension Array where Element == Profile {
    var formattedNamesString: String {
        let displayNames = self.map { $0.displayName }
            .filter { !$0.isEmpty }
            .sorted()

        switch displayNames.count {
        case 0:
            return ""
        case 1:
            return displayNames[0]
        case 2:
            return displayNames.joined(separator: " & ")
        default:
            let allButLast = displayNames.dropLast().joined(separator: ", ")
            let last = displayNames.last ?? ""
            return "\(allButLast) and \(last)"
        }
    }
}
