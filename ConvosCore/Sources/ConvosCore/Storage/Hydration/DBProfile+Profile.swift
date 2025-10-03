import Foundation

extension MemberProfile {
    func hydrateProfile() -> Profile {
        Profile(
            inboxId: inboxId,
            name: name,
            avatar: avatar
        )
    }
}
