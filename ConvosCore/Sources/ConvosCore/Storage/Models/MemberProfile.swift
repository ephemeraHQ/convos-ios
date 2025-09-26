import Foundation
import GRDB

public struct MemberProfile: Codable, FetchableRecord, PersistableRecord, Hashable {
    public enum Columns {
        static let conversationId: Column = Column(CodingKeys.conversationId)
        static let inboxId: Column = Column(CodingKeys.inboxId)
        static let name: Column = Column(CodingKeys.name)
        static let avatar: Column = Column(CodingKeys.avatar)
    }

    public let conversationId: String
    public let inboxId: String
    public let name: String?
    public let avatar: String?

    static let memberForeignKey: ForeignKey = ForeignKey([Columns.inboxId], to: [Member.Columns.inboxId])
    static let conversationForeignKey: ForeignKey = ForeignKey([Columns.conversationId], to: [DBConversation.Columns.id])

    static let member: BelongsToAssociation<MemberProfile, Member> = belongsTo(
        Member.self,
        using: memberForeignKey
    )

    static let conversation: BelongsToAssociation<MemberProfile, DBConversation> = belongsTo(
        DBConversation.self,
        using: conversationForeignKey
    )
}

extension MemberProfile {
    static func fetchOne(
        _ db: Database,
        conversationId: String,
        inboxId: String
    ) throws -> MemberProfile? {
        try fetchOne(
            db,
            key: [
                Columns.conversationId.name: conversationId,
                Columns.inboxId.name: inboxId
            ]
        )
    }

    static func fetchAll(
        _ db: Database,
        conversationId: String,
        inboxIds: [String]
    ) throws -> [MemberProfile] {
        let keys = inboxIds.map {
            [
                Columns.conversationId.name: conversationId,
                Columns.inboxId.name: $0
            ]
        }
        return try fetchAll(db, keys: keys)
    }

    func with(name: String?) -> MemberProfile {
        .init(
            conversationId: conversationId,
            inboxId: inboxId,
            name: name,
            avatar: avatar
        )
    }

    func with(avatar: String?) -> MemberProfile {
        .init(
            conversationId: conversationId,
            inboxId: inboxId,
            name: name,
            avatar: avatar
        )
    }
}
