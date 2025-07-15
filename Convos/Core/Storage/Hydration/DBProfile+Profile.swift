import Foundation

extension MemberProfile {
    func hydrateProfile() -> Profile {
        Profile(
            inboxId: inboxId,
            name: name,
            username: username.isEmpty ? inboxId : username,
            avatar: avatar
        )
    }
}
