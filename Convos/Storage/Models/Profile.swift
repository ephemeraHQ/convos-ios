import Foundation
import GRDB

struct UserProfile: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable {
    var id: String {
        userId
    }
    let userId: String // DBUser.id
    let name: String
    let username: String
    let avatar: String?
}

struct MemberProfile: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable {
    var id: String {
        inboxId
    }
    let inboxId: String
    let name: String
    let username: String
    let avatar: String?
    let isCurrentUser: Bool
}

struct Profile: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let username: String
    let avatar: String?
    let isCurrentUser: Bool

    var avatarURL: URL? {
        guard let avatar, let url = URL(string: avatar) else {
            return nil
        }
        return url
    }

    static var empty: Profile {
        .init()
    }

    init(id: String,
         name: String,
         username: String,
         avatar: String?,
         isCurrentUser: Bool) {
        self.id = id
        self.name = name
        self.username = username
        self.avatar = avatar
        self.isCurrentUser = isCurrentUser
    }

    private init() {
        self.id = UUID().uuidString
        self.name = ""
        self.username = ""
        self.avatar = nil
        self.isCurrentUser = false
    }

    init(from memberProfile: MemberProfile) {
        self.id = "member_\(memberProfile.inboxId)"
        self.name = memberProfile.name
        self.username = memberProfile.username
        self.avatar = memberProfile.avatar
        self.isCurrentUser = memberProfile.isCurrentUser
    }

    init(from userProfile: UserProfile) {
        self.id = "user_\(userProfile.id)"
        self.name = userProfile.name
        self.username = userProfile.username
        self.avatar = userProfile.avatar
        self.isCurrentUser = true
    }
}
