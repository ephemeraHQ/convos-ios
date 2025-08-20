import Foundation
import GRDB

struct Session: Codable, FetchableRecord, PersistableRecord, TableRecord, Identifiable {
    static let databaseTableName: String = "session"
    static let defaultSessionId: Int64 = 1
    var id: Int64 = Self.defaultSessionId

    static let inboxes: HasManyAssociation<Session, DBInbox> = hasMany(
        DBInbox.self,
        key: "sessionInboxes",
        using: ForeignKey(["id"], to: ["sessionId"])
    )

    static let profiles: HasManyThroughAssociation<Session, MemberProfile> = hasMany(
        MemberProfile.self,
        through: inboxes.forKey("profilesInboxes"),
        using: DBInbox.memberProfile,
        key: "sessionMemberProfiles"
    )
}

public struct CurrentSession: Codable, Hashable {
    let inboxes: [Inbox]
}
