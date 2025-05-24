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
