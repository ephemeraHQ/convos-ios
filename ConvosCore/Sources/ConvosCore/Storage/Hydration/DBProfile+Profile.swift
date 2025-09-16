import Foundation

extension MemberProfile {
    func hydrateProfile() -> Profile {
        Profile(
            inboxId: inboxId,
            name: name,
            avatar: avatar
        )
    }

    func asUpdateRequest() -> ConvosAPI.UpdateProfileRequest {
        .init(name: name, avatar: avatar)
    }
}
