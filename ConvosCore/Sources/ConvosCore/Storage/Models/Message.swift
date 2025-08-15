import Foundation

protocol MessageType {
    var id: String { get }
    var conversation: Conversation { get }
    var sender: ConversationMember { get }
    var source: MessageSource { get }
    var status: MessageStatus { get }
    var content: MessageContent { get }
    var date: Date { get }
}

enum AnyMessage: Hashable, Codable {
    case message(Message),
         reply(MessageReply)

    var base: MessageType {
        switch self {
        case .message(let message):
            return message
        case .reply(let reply):
            return reply
        }
    }
}

enum MessageContent: Hashable, Codable {
    case text(String),
         emoji(String), // all emoji, not a reaction
         attachment(URL),
         attachments([URL]),
         update(ConversationUpdate)

    var showsSender: Bool {
        switch self {
        case .update:
            false
        default:
            true
        }
    }
}

struct Message: MessageType, Hashable, Codable {
    let id: String
    let conversation: Conversation
    let sender: ConversationMember
    let source: MessageSource
    let status: MessageStatus
    let content: MessageContent
    let date: Date

    let reactions: [MessageReaction]
}

struct MessageReply: MessageType, Hashable, Codable {
    let id: String
    let conversation: Conversation
    let sender: ConversationMember
    let source: MessageSource
    let status: MessageStatus
    let content: MessageContent
    let date: Date

    let parentMessage: Message
    let reactions: [MessageReaction]
}

struct MessageReaction: MessageType, Hashable, Codable {
    let id: String
    let conversation: Conversation
    let sender: ConversationMember
    let source: MessageSource
    let status: MessageStatus
    let content: MessageContent
    let date: Date

    let emoji: String // same as content.text
}
