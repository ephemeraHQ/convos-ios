import Foundation
import GRDB

enum ConversationKind: Hashable, Codable {
    case group, dm
}

struct MessagePreview: Codable, Equatable, Hashable {
    let text: String
    let createdAt: Date
}

struct DBConversation: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable {
    static var databaseTableName: String = "conversation"
    enum Consent: Hashable, Codable {
        case allowed, denied, unknown
    }

    let id: String
    let isCreator: Bool
    let kind: ConversationKind
    let consent: Consent
    let createdAt: Date
    let topic: String
    let creatorId: String
    let memberIds: [String]
    let imageURLString: String?
    var lastMessage: MessagePreview?
}

struct Conversation: Codable, Hashable, Identifiable {
    let id: String
    let creator: Profile
    let kind: ConversationKind
    let topic: String
    let members: [Profile]
    let messages: [Message]
    let isPinned: Bool
    let isUnread: Bool
    let isMuted: Bool
    let lastMessage: MessagePreview?
    let imageURL: URL?

    var otherMember: Profile? {
        switch kind {
        case .dm:
            return members.first(where: { $0.id != creator.id })
        case .group:
            return nil
        }
    }
}

struct ConversationLocalState: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable {
    var id: String // conversation.id
    let isPinned: Bool
    let isUnread: Bool
    let isMuted: Bool

    static var empty: ConversationLocalState {
        .init(id: "", isPinned: false, isUnread: false, isMuted: false)
    }
}
