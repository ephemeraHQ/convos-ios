import Foundation

extension UserProfile {
    func hydrateProfile() -> Profile {
        Profile(id: "user_\(id)",
                name: name,
                username: username,
                avatar: avatar)
    }
}

extension MemberProfile {
    func hydrateProfile() -> Profile {
        Profile(id: "member_\(inboxId)",
                name: name,
                username: username.isEmpty ? inboxId : username,
                avatar: avatar)
    }
}
