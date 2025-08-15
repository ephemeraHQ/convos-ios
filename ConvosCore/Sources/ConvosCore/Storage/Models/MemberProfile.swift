import Foundation
import GRDB

struct MemberProfile: Codable, FetchableRecord, PersistableRecord, Hashable {
    let inboxId: String
    let name: String?
    let avatar: String?

    static let memberForeignKey: ForeignKey = ForeignKey(["inboxId"], to: ["inboxId"])

    static let member: BelongsToAssociation<MemberProfile, Member> = belongsTo(
        Member.self,
        using: memberForeignKey
    )
}

extension MemberProfile {
    func with(name: String?) -> MemberProfile {
        .init(inboxId: inboxId, name: name, avatar: avatar)
    }

    func with(avatar: String?) -> MemberProfile {
        .init(inboxId: inboxId, name: name, avatar: avatar)
    }
}
