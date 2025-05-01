import Foundation

struct CTUser: Identifiable, Equatable {
    let id: String
    let username: String
    let avatarURL: URL

    static func == (lhs: CTUser, rhs: CTUser) -> Bool {
        lhs.id == rhs.id
    }
}

struct CTMessage: Identifiable, Equatable {
    let id: String
    let content: String
    let sender: CTUser
    let timestamp: Date

    static func == (lhs: CTMessage, rhs: CTMessage) -> Bool {
        lhs.id == rhs.id
    }
}

struct CTConversation: Identifiable, Equatable {
    let id: String
    let participants: [CTUser]
    var lastMessage: CTMessage?
    var isPinned: Bool
    var isUnread: Bool
    var isRequest: Bool
    var isMuted: Bool
    let timestamp: Date
    var amount: Double?

    var otherParticipant: CTUser? {
        // For now, assuming 1:1 chats, return the other participant
        participants.first
    }

    static func == (lhs: CTConversation, rhs: CTConversation) -> Bool {
        lhs.id == rhs.id &&
        lhs.participants == rhs.participants &&
        lhs.lastMessage == rhs.lastMessage &&
        lhs.isPinned == rhs.isPinned &&
        lhs.isUnread == rhs.isUnread &&
        lhs.isRequest == rhs.isRequest &&
        lhs.isMuted == rhs.isMuted &&
        lhs.amount == rhs.amount &&
        lhs.timestamp == rhs.timestamp
    }
}

enum CTConversationIndicator {
    case unread
    case muted
    case none
}
