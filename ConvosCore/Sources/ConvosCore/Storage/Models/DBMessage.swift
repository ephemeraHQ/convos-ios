import Foundation
import GRDB

public enum MessageStatus: String, Hashable, Codable {
    case unpublished, published, failed, unknown
}

public enum MessageSource: String, Hashable, Codable {
    case incoming, outgoing

    public var isIncoming: Bool {
        self == .incoming
    }
}

public enum DBMessageType: String, Codable {
    case original,
         reply,
         reaction
}

public enum MessageContentType: String, Codable {
    case text, emoji, attachments, update

    var marksConversationAsUnread: Bool {
        switch self {
        case .update:
            false
        default:
            true
        }
    }
}

struct DBMessage: FetchableRecord, PersistableRecord, Hashable, Codable {
    static var databaseTableName: String = "message"

    struct Update: Codable, Hashable {
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

    enum Columns {
        static let id: Column = Column(CodingKeys.id)
        static let clientMessageId: Column = Column(CodingKeys.clientMessageId)
        static let conversationId: Column = Column(CodingKeys.conversationId)
        static let senderId: Column = Column(CodingKeys.senderId)
        static let date: Column = Column(CodingKeys.date)
        static let dateNs: Column = Column(CodingKeys.dateNs)
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
    let dateNs: Int64
    let date: Date
    let status: MessageStatus

    let messageType: DBMessageType
    let contentType: MessageContentType

    // content
    let text: String?
    let emoji: String?
    let sourceMessageId: String? // replies and reactions
    let attachmentUrls: [String]
    let update: Update?

    var attachmentUrl: String? {
        attachmentUrls.first
    }

    static let sourceMessageForeignKey: ForeignKey = ForeignKey([Columns.sourceMessageId], to: [Columns.id])
    static let senderForeignKey: ForeignKey = ForeignKey(
        [
            Columns.senderId,
            Columns.conversationId
        ],
        to: [
            DBConversationMember.Columns.inboxId,
            DBConversationMember.Columns.conversationId
        ]
    )
    static let conversationForeignKey: ForeignKey = ForeignKey([Columns.conversationId], to: [DBConversation.Columns.id])

    static let conversation: HasOneAssociation<DBMessage, DBConversation> = hasOne(
        DBConversation.self,
        using: conversationForeignKey
    )

    static let sender: BelongsToAssociation<DBMessage, DBConversationMember> = belongsTo(
        DBConversationMember.self,
        key: "messageSender",
        using: senderForeignKey
    )

    static let senderProfile: HasOneThroughAssociation<DBMessage, MemberProfile> = hasOne(
        MemberProfile.self,
        through: sender,
        using: DBConversationMember.memberProfile,
        key: "messageSenderProfile"
    )

    static let replies: HasManyAssociation<DBMessage, DBMessage> = hasMany(
        DBMessage.self,
        key: "messageReplies",
        using: ForeignKey([Columns.id], to: [Columns.sourceMessageId])
    ).filter(DBMessage.Columns.messageType == DBMessageType.reply.rawValue)

    static let reactions: HasManyAssociation<DBMessage, DBMessage> = hasMany(
        DBMessage.self,
        key: "messageReactions",
        using: ForeignKey([Columns.id], to: [Columns.sourceMessageId]),
    ).filter(DBMessage.Columns.messageType == DBMessageType.reaction.rawValue)

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
            dateNs: dateNs,
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
            dateNs: dateNs,
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

    func with(date: Date) -> DBMessage {
        .init(
            id: id,
            clientMessageId: clientMessageId,
            conversationId: conversationId,
            senderId: senderId,
            dateNs: dateNs,
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
            dateNs: dateNs,
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
