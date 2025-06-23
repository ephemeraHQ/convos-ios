import Foundation
import GRDB

struct Inbox: Codable, Identifiable, Hashable {
    var id: String { inboxId }
    let inboxId: String
    let identities: [Identity]
    let profile: Profile
    let type: InboxType
    let provider: InboxProvider
    let providerId: String
}

enum InboxType: String, Codable {
    case standard, ephemeral
}

enum InboxProvider: String, Codable {
    case local, external
}

struct DBInbox: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable {
    static let databaseTableName: String = "inbox"

    var id: String { inboxId }
    var sessionId: Int64 = Session.defaultSessionId
    let inboxId: String
    let type: InboxType
    let provider: InboxProvider
    let providerId: String

    static let identities: HasManyAssociation<DBInbox, Identity> = hasMany(
        Identity.self,
        key: "inboxIdentities",
        using: ForeignKey(["inboxId"], to: ["inboxId"])
    )

    private static let _member: HasOneAssociation<DBInbox, Member> = hasOne(
        Member.self,
        key: "inboxMember"
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
