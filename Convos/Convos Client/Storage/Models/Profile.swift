import Foundation
import GRDB

struct UserProfile: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable {
    var id: String { userId }
    let userId: String // DBUser.id
    let name: String
    let username: String
    let avatar: String?

    static let user: BelongsToAssociation<UserProfile, DBUser> = belongsTo(
        DBUser.self
    )
}

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

enum MemberRole: String, Codable, Hashable {
    case member, admin, superAdmin = "super_admin"

    var displayName: String {
        switch self {
        case .member:
            return ""
        case .admin:
            return "Admin"
        case .superAdmin:
            return "Super Admin"
        }
    }

    var priority: Int {
        switch self {
        case .superAdmin: return 1
        case .admin: return 2
        case .member: return 3
        }
    }
}

struct Profile: Codable, Identifiable, Hashable {
    let id: String
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

struct ProfileWithRole: Codable, Identifiable, Hashable {
    let profile: Profile
    let role: MemberRole

    var id: String { profile.id }
    var displayName: String { profile.displayName }
    var username: String { profile.username }
    var avatar: String? { profile.avatar }
    var avatarURL: URL? { profile.avatarURL }

    init(profile: Profile, role: MemberRole) {
        self.profile = profile
        self.role = role
    }
}

// MARK: - Array Extensions

extension Array where Element == ProfileWithRole {
    func sortedByRole(currentUser: Profile?) -> [ProfileWithRole] {
        return self.sorted { member1, member2 in
            // Show current user first
            if let currentUser = currentUser {
                if member1.id == currentUser.id { return true }
                if member2.id == currentUser.id { return false }
            }
            // Fallback to hardcoded "current" for backwards compatibility
            if member1.id == "current" { return true }
            if member2.id == "current" { return false }

            // Sort by role hierarchy: superAdmin > admin > member
            let priority1 = member1.role.priority
            let priority2 = member2.role.priority

            if priority1 != priority2 {
                return priority1 < priority2
            }

            // Same role, sort alphabetically by name
            return member1.displayName < member2.displayName
        }
    }
}
