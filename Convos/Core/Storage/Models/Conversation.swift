import Foundation
import GRDB

// MARK: - Conversation

struct Conversation: Codable, Hashable, Identifiable, ImageCacheable {
    let id: String
    let inboxId: String
    let creator: ConversationMember
    let createdAt: Date
    let consent: Consent
    let kind: ConversationKind
    let name: String?
    let description: String?
    let members: [ConversationMember]
    let otherMember: ConversationMember?
    let messages: [Message]
    let isPinned: Bool
    let isUnread: Bool
    let isMuted: Bool
    let lastMessage: MessagePreview?
    let imageURL: URL?
    let isDraft: Bool
    let invite: Invite?

    var membersWithoutCurrent: [ConversationMember] {
        members.filter { !$0.isCurrentUser }
    }

    // MARK: - ImageCacheable
    var imageCacheIdentifier: String {
        id
    }
}

extension Conversation {
    var displayName: String {
        guard let name, !name.isEmpty else {
            return "Untitled"
        }
        return name
    }

    var memberNamesString: String {
        membersWithoutCurrent.formattedNamesString
    }

    var membersCountString: String {
        let totalCount = members.count
        return "\(totalCount) \(totalCount == 1 ? "person" : "people")"
    }
}
