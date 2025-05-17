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
        .init()
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

    private init() {
        self.id = UUID().uuidString
        self.name = ""
        self.username = ""
        self.avatar = nil
    }

    init(from memberProfile: MemberProfile) {
        self.id = "member_\(memberProfile.inboxId)"
        self.name = memberProfile.name
        self.username = (memberProfile.username.isEmpty ?
                         memberProfile.id : memberProfile.inboxId)
        self.avatar = memberProfile.avatar
    }

    init(from userProfile: UserProfile) {
        self.id = "user_\(userProfile.id)"
        self.name = userProfile.name
        self.username = userProfile.username
        self.avatar = userProfile.avatar
    }
}
