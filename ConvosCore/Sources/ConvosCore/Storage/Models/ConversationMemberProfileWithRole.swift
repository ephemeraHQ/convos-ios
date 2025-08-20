import Foundation
import GRDB

// MARK: - ConversationMemberProfileWithRole

struct ConversationMemberProfileWithRole: Codable, FetchableRecord, PersistableRecord, Hashable {
    let memberProfile: MemberProfile
    let role: MemberRole
}

extension ConversationMemberProfileWithRole {
    func hydrateConversationMember(currentInboxId: String) -> ConversationMember {
        .init(
            profile: memberProfile.hydrateProfile(),
            role: role,
            isCurrentUser: memberProfile.inboxId == currentInboxId
        )
    }
}
