import Foundation
import GRDB

// MARK: - DBInvite

struct DBInvite: Codable, FetchableRecord, PersistableRecord, Hashable {
    static var databaseTableName: String = "invite"

    enum Columns {
        static let creatorInboxId: Column = Column(CodingKeys.creatorInboxId)
        static let conversationId: Column = Column(CodingKeys.conversationId)
        static let urlSlug: Column = Column(CodingKeys.urlSlug)
    }

    let creatorInboxId: String
    let conversationId: String
    let urlSlug: String

    // Foreign key to the member who created this invite
    static let creatorForeignKey: ForeignKey = ForeignKey(
        [Columns.creatorInboxId, Columns.conversationId],
        to: [DBConversationMember.Columns.inboxId, DBConversationMember.Columns.conversationId]
    )

    static let creator: BelongsToAssociation<DBInvite, DBConversationMember> = belongsTo(
        DBConversationMember.self,
        key: "inviteCreator",
        using: creatorForeignKey
    )

    // Association to get the conversation through the creator
    static let conversation: HasOneThroughAssociation<DBInvite, DBConversation> = hasOne(
        DBConversation.self,
        through: creator,
        using: DBConversationMember.conversation,
        key: "inviteConversation"
    )
}
