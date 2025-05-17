import Foundation
import GRDB

enum MessageKind: Hashable, Codable {
    case text(String)
    case attachment(URL)
}

enum MessageStatus: Hashable, Codable {
    case unpublished, published, failed, unknown
}

enum MessageSource: Hashable, Codable {
    case incoming, outgoing

    var isIncoming: Bool {
        self == .incoming
    }
}

protocol MessageType: Codable, Identifiable, Hashable {
    var id: String { get }
    var conversationId: String { get }
    var sender: Profile { get }
    var date: Date { get }
    var source: MessageSource { get }
    var status: MessageStatus { get }
    var preview: String { get }
}

struct Message: MessageType, FetchableRecord, PersistableRecord {
    let id: String
    let conversationId: String
    let sender: Profile
    let date: Date
    let kind: MessageKind
    let source: MessageSource
    let status: MessageStatus

    var preview: String {
        switch kind {
        case .text(let text):
            return text
        case .attachment:
            return "Photo"
        }
    }
}

struct MessageReply: MessageType, FetchableRecord, PersistableRecord {
    let id: String
    let conversationId: String
    let sender: Profile
    let date: Date
    let kind: MessageKind
    let source: MessageSource
    let status: MessageStatus
    let sourceMessageId: String

    var preview: String {
        switch kind {
        case .text(let text):
            return "Replied \"\(text)\""
        case .attachment:
            return "Photo"
        }
    }
}

struct MessageReaction: MessageType, FetchableRecord, PersistableRecord {
    let id: String
    let conversationId: String
    let sender: Profile
    let date: Date
    let source: MessageSource
    let status: MessageStatus
    let sourceMessageId: String
    let emoji: String

    var preview: String {
        return emoji
    }
}
