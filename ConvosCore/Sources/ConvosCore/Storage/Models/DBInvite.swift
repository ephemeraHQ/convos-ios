import Foundation
import GRDB

// MARK: - DBInvite

public enum InviteStatus: String, Codable {
    case active, expired, disabled
}

struct DBInvite: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable {
    static var databaseTableName: String = "invite"

    enum Columns {
        static let id: Column = Column(CodingKeys.id)
        static let conversationId: Column = Column(CodingKeys.conversationId)
        static let inviteUrlString: Column = Column(CodingKeys.inviteUrlString)
        static let maxUses: Column = Column(CodingKeys.maxUses)
        static let usesCount: Column = Column(CodingKeys.usesCount)
        static let status: Column = Column(CodingKeys.status)
        static let createdAt: Column = Column(CodingKeys.createdAt)
        static let autoApprove: Column = Column(CodingKeys.autoApprove)
    }

    let id: String
    let conversationId: String
    let inviteUrlString: String
    let maxUses: Int?
    let usesCount: Int
    let status: InviteStatus
    let createdAt: Date
    let autoApprove: Bool

    static let conversationForeignKey: ForeignKey = ForeignKey(
        [Columns.conversationId],
        to: [DBConversation.Columns.id]
    )

    static let conversation: BelongsToAssociation<DBInvite, DBConversation> = belongsTo(
        DBConversation.self,
        key: "inviteConversation",
        using: conversationForeignKey
    )
}
