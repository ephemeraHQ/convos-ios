import Foundation
import GRDB

struct DBInbox: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable {
    static let databaseTableName: String = "inbox"

    enum Columns {
        static let sessionId: Column = Column(CodingKeys.sessionId)
        static let inboxId: Column = Column(CodingKeys.inboxId)
        static let type: Column = Column(CodingKeys.type)
        static let provider: Column = Column(CodingKeys.provider)
        static let providerId: Column = Column(CodingKeys.providerId)
    }

    var id: String { inboxId }
    var sessionId: Int64 = Session.defaultSessionId
    let inboxId: String
    let type: InboxType
    let provider: InboxProvider
    let providerId: String

    static let conversations: HasManyAssociation<DBInbox, DBConversation> = hasMany(
        DBConversation.self,
        key: "conversations",
        using: ForeignKey([Columns.inboxId], to: [DBConversation.Columns.inboxId])
    )

    static let identities: HasManyAssociation<DBInbox, Identity> = hasMany(
        Identity.self,
        key: "inboxIdentities",
        using: ForeignKey(["inboxId"], to: ["inboxId"])
    )

    private static let _member: HasOneAssociation<DBInbox, Member> = hasOne(
        Member.self,
        key: "inboxMember",
        using: ForeignKey(["inboxId"], to: ["inboxId"])
    )

    static let memberProfile: HasOneThroughAssociation<DBInbox, MemberProfile> = hasOne(
        MemberProfile.self,
        through: _member.forKey("inboxMember"),
        using: Member.profile,
        key: "inboxMemberProfile"
    )
}

struct DBInboxDetails: Codable, FetchableRecord, PersistableRecord, Hashable {
    let inbox: DBInbox
    let inboxIdentities: [Identity]
    let inboxMemberProfile: MemberProfile
}
