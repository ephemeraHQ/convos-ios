import Foundation
import GRDB

struct Inbox: Codable, Identifiable, Hashable {
    var id: String { inboxId }
    let inboxId: String
    let identities: [Identity]
    let profile: Profile
}

struct DBInbox: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable {
    static let databaseTableName: String = "inbox"

    var id: String { inboxId }
    let inboxId: String
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

struct Identity: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable {
    let id: String
    let inboxId: String
    let walletAddress: String

    static let inboxForeignKey: ForeignKey = ForeignKey(["inboxId"])

    static let inbox: BelongsToAssociation<Identity, DBInbox> = belongsTo(
        DBInbox.self,
        key: "identityInbox",
        using: inboxForeignKey
    )
}

struct Session: Codable, FetchableRecord, PersistableRecord, TableRecord, Identifiable {
    static let databaseTableName: String = "session"
    var id: Int64 = 1

    static let inboxes: HasManyAssociation<Session, DBInbox> = hasMany(
        DBInbox.self,
        key: "sessionInboxes",
        using: ForeignKey(["inboxId"], to: ["inboxId"])
    )

    static let profiles: HasManyThroughAssociation<Session, MemberProfile> = hasMany(
        MemberProfile.self,
        through: inboxes.forKey("profilesInboxes"),
        using: DBInbox.memberProfile,
        key: "sessionMemberProfiles"
    )
}

struct CurrentSessionDetails: Codable, FetchableRecord, PersistableRecord, Hashable {
    let sessionInboxes: [DBInbox]
}

struct CurrentSession: Codable, Hashable {
    let inboxes: [Inbox]
}
