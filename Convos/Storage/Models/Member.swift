import Foundation
import GRDB

// TODO: Not needed?
struct Member: Codable, FetchableRecord, PersistableRecord, Hashable {
    let inboxId: String

    static let profileForeignKey: ForeignKey = ForeignKey(["inboxId"], to: ["inboxId"])

    static let profile: HasOneAssociation<Member, MemberProfile> = hasOne(
        MemberProfile.self,
        using: profileForeignKey
    )
}
