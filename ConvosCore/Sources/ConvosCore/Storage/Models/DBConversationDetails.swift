import Foundation
import GRDB

// MARK: - DBConversationDetails

struct DBConversationDetails: Codable, FetchableRecord, PersistableRecord, Hashable {
    let conversation: DBConversation
    let conversationCreator: ConversationMemberProfileWithRole
    let conversationMembers: [ConversationMemberProfileWithRole]
    let conversationLastMessage: DBMessage?
    let conversationLocalState: ConversationLocalState
    let conversationInvite: DBInvite?
}

extension DBConversationDetails {
    func hydrateConversationMembers(currentInboxId: String) -> [ConversationMember] {
        return conversationMembers.compactMap { member in
            member.hydrateConversationMember(currentInboxId: currentInboxId)
        }
    }
}
