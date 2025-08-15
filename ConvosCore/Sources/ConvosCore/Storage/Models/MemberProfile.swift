import Foundation
import GRDB

public struct MemberProfile: Codable, FetchableRecord, PersistableRecord, Hashable {
    public let inboxId: String
    public let name: String?
    public let avatar: String?

    public init(inboxId: String, name: String?, avatar: String?) {
        self.inboxId = inboxId
        self.name = name
        self.avatar = avatar
    }

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
