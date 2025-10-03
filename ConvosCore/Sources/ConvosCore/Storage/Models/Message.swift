import Foundation

public protocol MessageType {
    var id: String { get }
    var conversation: Conversation { get }
    var sender: ConversationMember { get }
    var source: MessageSource { get }
    var status: MessageStatus { get }
    var content: MessageContent { get }
    var date: Date { get }
}

public enum AnyMessage: Hashable, Codable {
    case message(Message),
         reply(MessageReply)

    public var base: MessageType {
        switch self {
        case .message(let message):
            return message
        case .reply(let reply):
            return reply
        }
    }
}

public enum MessageContent: Hashable, Codable {
    case text(String),
         emoji(String), // all emoji, not a reaction
         attachment(URL),
         attachments([URL]),
         update(ConversationUpdate)

    public var showsInMessagesList: Bool {
        switch self {
        case .update(let update):
            return update.showsInMessagesList
        default:
            return true
        }
    }

    public var showsSender: Bool {
        switch self {
        case .update:
            false
        default:
            true
        }
    }
}

public struct Message: MessageType, Hashable, Codable {
    public let id: String
    public let conversation: Conversation
    public let sender: ConversationMember
    public let source: MessageSource
    public let status: MessageStatus
    public let content: MessageContent
    public let date: Date

    public let reactions: [MessageReaction]
}

public struct MessageReply: MessageType, Hashable, Codable {
    public let id: String
    public let conversation: Conversation
    public let sender: ConversationMember
    public let source: MessageSource
    public let status: MessageStatus
    public let content: MessageContent
    public let date: Date

    public let parentMessage: Message
    public let reactions: [MessageReaction]
}

public struct MessageReaction: MessageType, Hashable, Codable {
    public let id: String
    public let conversation: Conversation
    public let sender: ConversationMember
    public let source: MessageSource
    public let status: MessageStatus
    public let content: MessageContent
    public let date: Date

    public let emoji: String // same as content.text
}
