import Foundation
import GRDB

enum MessageStatus: String, Hashable, Codable {
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
    case text, emoji, attachments, update
}

struct DBConversationUpdate: Codable, Hashable {
    struct MetadataChange: Codable, Hashable {
        let field: String
        let oldValue: String?
        let newValue: String?
    }

    let initiatedByInboxId: String
    let addedInboxIds: [String]
    let removedInboxIds: [String]
    let metadataChanges: [MetadataChange]
}

struct DBMessage: FetchableRecord, PersistableRecord, Hashable, Codable {
    static var databaseTableName: String = "message"

    enum Columns {
        static let id: Column = Column(CodingKeys.id)
        static let clientMessageId: Column = Column(CodingKeys.clientMessageId)
        static let conversationId: Column = Column(CodingKeys.conversationId)
        static let senderId: Column = Column(CodingKeys.senderId)
        static let date: Column = Column(CodingKeys.date)
        static let status: Column = Column(CodingKeys.status)
        static let messageType: Column = Column(CodingKeys.messageType)
        static let contentType: Column = Column(CodingKeys.contentType)
        static let text: Column = Column(CodingKeys.text)
        static let emoji: Column = Column(CodingKeys.emoji)
        static let sourceMessageId: Column = Column(CodingKeys.sourceMessageId)
        static let attachmentUrls: Column = Column(CodingKeys.attachmentUrls)
    }

    let id: String // external
    let clientMessageId: String // always the same, used for optimistic send
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
    let update: DBConversationUpdate?

    var attachmentUrl: String? {
        attachmentUrls.first
    }

    static let sourceMessageForeignKey: ForeignKey = ForeignKey(["sourceMessageId"], to: ["id"])
    static let senderForeignKey: ForeignKey = ForeignKey(["senderId"], to: ["inboxId"])
    static let conversationForeignKey: ForeignKey = ForeignKey(["conversationId"], to: ["id"])

    static let conversation: HasOneAssociation<DBMessage, DBConversation> = hasOne(
        DBConversation.self,
        using: conversationForeignKey
    )

    static let sender: BelongsToAssociation<DBMessage, Member> = belongsTo(
        Member.self,
        key: "messageSender",
        using: senderForeignKey
    )

    static let senderProfile: HasOneThroughAssociation<DBMessage, MemberProfile> = hasOne(
        MemberProfile.self,
        through: sender,
        using: Member.profile,
        key: "messageSenderProfile"
    )

    static let replies: HasManyAssociation<DBMessage, DBMessage> = hasMany(
        DBMessage.self,
        key: "messageReplies",
        using: ForeignKey(["id"], to: ["sourceMessageId"])
    ).filter(Column("messageType") == DBMessageType.reply.rawValue)

    static let reactions: HasManyAssociation<DBMessage, DBMessage> = hasMany(
        DBMessage.self,
        key: "messageReactions",
        using: ForeignKey(["id"], to: ["sourceMessageId"]),
    ).filter(Column("messageType") == DBMessageType.reaction.rawValue)

    static let sourceMessage: BelongsToAssociation<DBMessage, DBMessage> = belongsTo(
        DBMessage.self,
        key: "sourceMessage",
        using: sourceMessageForeignKey
    )
}

extension DBMessage {
    func with(id: String) -> DBMessage {
        .init(
            id: id,
            clientMessageId: clientMessageId,
            conversationId: conversationId,
            senderId: senderId,
            date: date,
            status: status,
            messageType: messageType,
            contentType: contentType,
            text: text,
            emoji: emoji,
            sourceMessageId: sourceMessageId,
            attachmentUrls: attachmentUrls,
            update: update
        )
    }

    func with(clientMessageId: String) -> DBMessage {
        .init(
            id: id,
            clientMessageId: clientMessageId,
            conversationId: conversationId,
            senderId: senderId,
            date: date,
            status: status,
            messageType: messageType,
            contentType: contentType,
            text: text,
            emoji: emoji,
            sourceMessageId: sourceMessageId,
            attachmentUrls: attachmentUrls,
            update: update
        )
    }

    func with(conversationId: String) -> DBMessage {
        .init(
            id: id,
            clientMessageId: clientMessageId,
            conversationId: conversationId,
            senderId: senderId,
            date: date,
            status: status,
            messageType: messageType,
            contentType: contentType,
            text: text,
            emoji: emoji,
            sourceMessageId: sourceMessageId,
            attachmentUrls: attachmentUrls,
            update: update
        )
    }
 }

struct MessageWithDetails: Codable, FetchableRecord, PersistableRecord, Hashable {
    let message: DBMessage
    let messageSenderProfile: MemberProfile
    let messageReactions: [DBMessage]
    let sourceMessage: DBMessage?
}

struct MessageWithDetailsAndReplies: Codable, FetchableRecord, PersistableRecord, Hashable {
    let message: DBMessage
    let sender: MemberProfile
    let reactions: [DBMessage]
    let replies: [DBMessage]
}

protocol MessageType {
    var id: String { get }
    var conversation: Conversation { get }
    var sender: Profile { get }
    var source: MessageSource { get }
    var status: MessageStatus { get }
    var content: MessageContent { get }
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
    let source: MessageSource
    let status: MessageStatus
    let content: MessageContent

    let reactions: [MessageReaction]
}

struct MessageReply: MessageType, Hashable, Codable {
    let id: String
    let conversation: Conversation
    let sender: Profile
    let source: MessageSource
    let status: MessageStatus
    let content: MessageContent

    let parentMessage: Message
    let reactions: [MessageReaction]
}

struct MessageReaction: MessageType, Hashable, Codable {
    let id: String
    let conversation: Conversation
    let sender: Profile
    let source: MessageSource
    let status: MessageStatus
    let content: MessageContent

    let emoji: String // same as content.text
}
