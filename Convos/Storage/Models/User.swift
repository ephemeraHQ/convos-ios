import Foundation
import GRDB

struct DBUser: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable {
    let id: String

    static let databaseTableName: String = "user"

    static let profile: HasOneAssociation<DBUser, UserProfile> = hasOne(
        UserProfile.self,
        key: "userProfile"
    )

    static let identities: HasManyAssociation<DBUser, Identity> = hasMany(
        Identity.self,
        key: "userIdentities",
        using: ForeignKey(["userId"], to: ["id"])
    )
}

struct User: Codable, Identifiable, Hashable {
    let id: String
    let identities: [Identity]
    let profile: Profile
}

struct Identity: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable {
    let id: String
    let userId: String
    let walletAddress: String
    let xmtpId: String?

    static let userForeignKey: ForeignKey = ForeignKey(["userId"])

    static let user: BelongsToAssociation<Identity, DBUser> = belongsTo(
        DBUser.self,
        key: "identityUser",
        using: userForeignKey
    )
}

struct Session: Codable, FetchableRecord, PersistableRecord, TableRecord, Identifiable {
    static let databaseTableName: String = "session"
    var id: Int64 = 1
    var userId: String

    static let user: BelongsToAssociation<Session, DBUser> = belongsTo(
        DBUser.self,
        key: "sessionUser",
        using: ForeignKey(["userId"], to: ["id"])
    )

    static let identities: HasManyThroughAssociation<Session, Identity> = hasMany(
        Identity.self,
        through: user.forKey("identitiesUser"),
        using: DBUser.identities,
        key: "sessionIdentities"
    )

    static let profile: HasOneThroughAssociation<Session, UserProfile> = hasOne(
        UserProfile.self,
        through: user.forKey("profileUser"),
        using: DBUser.profile,
        key: "sessionProfile"
    )
}

struct CurrentSessionDetails: Codable, FetchableRecord, PersistableRecord, Hashable {
    let sessionUser: DBUser
    let sessionIdentities: [Identity]
    let sessionProfile: UserProfile
}
