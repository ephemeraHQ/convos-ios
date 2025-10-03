import Foundation
import GRDB

// MARK: - DBConversationMember

struct DBConversationMember: Codable, FetchableRecord, PersistableRecord, Hashable {
    enum Columns {
        static let conversationId: Column = Column(CodingKeys.conversationId)
        static let inboxId: Column = Column(CodingKeys.inboxId)
        static let role: Column = Column(CodingKeys.role)
        static let consent: Column = Column(CodingKeys.consent)
        static let createdAt: Column = Column(CodingKeys.createdAt)
    }

    let conversationId: String
    let inboxId: String
    let role: MemberRole
    let consent: Consent
    let createdAt: Date

    static var databaseTableName: String { "conversation_members" }

    static let memberForeignKey: ForeignKey = ForeignKey(["inboxId"], to: ["inboxId"])
    static let conversationForeignKey: ForeignKey = ForeignKey(["conversationId"])

    // Foreign key to match invites created by this member for this conversation
    static let inviteForeignKey: ForeignKey = ForeignKey(
        [DBInvite.Columns.creatorInboxId, DBInvite.Columns.conversationId],
        to: [Columns.inboxId, Columns.conversationId]
    )

    static let invite: HasOneAssociation<DBConversationMember, DBInvite> = hasOne(
        DBInvite.self,
        key: "memberInvite",
        using: inviteForeignKey
    )

    static let conversation: BelongsToAssociation<DBConversationMember, DBConversation> = belongsTo(
        DBConversation.self,
        using: conversationForeignKey
    )

    static let member: BelongsToAssociation<DBConversationMember, Member> = belongsTo(
        Member.self,
        using: memberForeignKey
    )

    static let memberProfileForeignKey: ForeignKey = ForeignKey(
        [Columns.conversationId, Columns.inboxId],
        to: [MemberProfile.Columns.conversationId, MemberProfile.Columns.inboxId]
    )

    static let memberProfile: HasOneAssociation<DBConversationMember, MemberProfile> = hasOne(
        MemberProfile.self,
        using: memberProfileForeignKey
    )
}

// MARK: - DBConversationMember Extensions

extension DBConversationMember {
    func with(role: MemberRole) -> Self {
        .init(
            conversationId: conversationId,
            inboxId: inboxId,
            role: role,
            consent: consent,
            createdAt: createdAt
        )
    }
}
