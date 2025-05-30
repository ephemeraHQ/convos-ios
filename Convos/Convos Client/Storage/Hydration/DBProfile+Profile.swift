import Foundation

extension UserProfile {
    func hydrateProfile() -> Profile {
        Profile(id: id,
                name: name,
                username: username,
                avatar: avatar)
    }
}

extension MemberProfile {
    func hydrateProfile() -> Profile {
        Profile(id: inboxId,
                name: name,
                username: username.isEmpty ? inboxId : username,
                avatar: avatar)
    }
}
