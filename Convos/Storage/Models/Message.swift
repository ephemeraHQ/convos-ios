import Foundation
import GRDB

enum MessageStatus: Hashable, Codable {
    case unpublished, published, failed, unknown
}

enum MessageSource: Hashable, Codable {
    case incoming, outgoing

    var isIncoming: Bool {
        self == .incoming
    }
}

enum DBMessageType: String, Codable {
    case original,
         reply,
         reaction
}

enum MessageContentType: String, Codable {
    case text, emoji, attachments
}

struct DBMessage: FetchableRecord, PersistableRecord, Hashable, Codable {
    static var databaseTableName: String = "message"

    enum Columns {
        static let id: Column = Column("id")
        static let conversationId: Column = Column("conversationId")
        static let senderId: Column = Column("senderId")
        static let date: Column = Column("date")
        static let status: Column = Column("status")
        static let messageType: Column = Column("messageType")
        static let contentType: Column = Column("contentType")
        static let text: Column = Column("text")
        static let emoji: Column = Column("emoji")
        static let sourceMessageId: Column = Column("sourceMessageId")
        static let attachmentUrls: Column = Column("attachmentUrls")
    }

    let id: String
    let conversationId: String
    let senderId: String
    let date: Date
    let status: MessageStatus

    let messageType: DBMessageType
    let contentType: MessageContentType

    // content
    let text: String?
    let emoji: String?
    let sourceMessageId: String? // replies and reactions
    let attachmentUrls: [String]

    var attachmentUrl: String? {
        attachmentUrls.first
    }

    var preview: String {
        switch messageType {
        case .original:
            ""
        case .reply:
            ""
        case .reaction:
            ""
        }
    }

    static let conversation: HasOneAssociation<DBMessage, DBConversation> = hasOne(
        DBConversation.self
    )

    static let sender: BelongsToAssociation<DBMessage, Member> = belongsTo(
        Member.self
    )

    static let replies: HasManyAssociation<DBMessage, DBMessage> = hasMany(
        DBMessage.self,
        using: ForeignKey(["sourceMessageId"])
    ).filter(Column("messageType") == DBMessageType.reply.rawValue)

    static let reactions: HasManyAssociation<DBMessage, DBMessage> = hasMany(
        DBMessage.self,
        using: ForeignKey(
            ["sourceMessageId"]
        )
    ).filter(Column("messageType") == DBMessageType.reaction.rawValue)

//    static let sourceMessage: BelongsToAssociation<DBMessage, DBMessage?> = belongsTo(
//        DBMessage.self
//    )
}

struct MessageWithDetails: FetchableRecord {
    let message: DBMessage
    let sender: MemberProfile
    let reactions: [DBMessage]

    init(row: GRDB.Row) throws {
        message = try DBMessage(row: row)
        guard let conversationRow = row.scopes["conversation"],
              let senderRow = row.scopes["sender"],
        let reactionsRow = row.prefetchedRows["reactions"] else {
            throw DatabaseError(
                message: "Missing required scopes 'conversation' or 'sender' in MessageWithConversationAndSender"
            )
        }
        sender = try MemberProfile(row: senderRow)
        reactions = try reactionsRow.map { try DBMessage(row: $0) }
    }
}

struct MessageWithDetailsAndReplies: FetchableRecord {
    let message: DBMessage
    let sender: MemberProfile
    let reactions: [DBMessage]
    let replies: [DBMessage]

    init(row: GRDB.Row) throws {
        message = try DBMessage(row: row)
        guard let conversationRow = row.scopes["conversation"],
              let senderRow = row.scopes["sender"],
              let reactionsRow = row.prefetchedRows["reactions"],
        let repliesRow = row.prefetchedRows["replies"] else {
            throw DatabaseError(
                message: "Missing required scopes 'conversation' or 'sender' in MessageWithConversationAndSender"
            )
        }
        sender = try MemberProfile(row: senderRow)
        reactions = try reactionsRow.map { try DBMessage(row: $0) }
        replies = try repliesRow.map { try DBMessage(row: $0) }
    }
}

protocol MessageType {
    var id: String { get }
    var conversation: Conversation { get }
    var sender: Profile { get }
    var source: MessageSource { get }
    var status: MessageStatus { get }
    var content: MessageContent { get }
}

extension MessageType {
    var source: MessageSource {
        return .incoming
    }
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
         attachments([URL])
}

struct Message: MessageType, Hashable, Codable {
    let id: String
    let conversation: Conversation
    let sender: Profile
    let status: MessageStatus
    let content: MessageContent

    let reactions: [MessageReaction]
}

struct MessageReply: MessageType, Hashable, Codable {
    let id: String
    let conversation: Conversation
    let sender: Profile
    let status: MessageStatus
    let content: MessageContent

    let parentMessage: Message
    let reactions: [MessageReaction]
}

struct MessageReaction: MessageType, Hashable, Codable {
    let id: String
    let conversation: Conversation
    let sender: Profile
    let status: MessageStatus
    let content: MessageContent

    let emoji: String // same as content.text
}
