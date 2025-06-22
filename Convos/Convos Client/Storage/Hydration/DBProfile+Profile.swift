import Foundation

extension MemberProfile {
    func hydrateProfile() -> Profile {
        Profile(id: inboxId,
                name: name,
                username: username.isEmpty ? inboxId : username,
                avatar: avatar)
    }
}
