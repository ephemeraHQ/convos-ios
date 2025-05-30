import Foundation
import GRDB

enum ConversationKind: Hashable, Codable {
    case group, dm
}

struct MessagePreview: Codable, Equatable, Hashable {
    let text: String
    let createdAt: Date
}

struct DBConversation: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable {
    static var databaseTableName: String = "conversation"

    enum Consent: Hashable, Codable {
        case allowed, denied, unknown
    }

    enum Columns {
        static let id: Column = Column(CodingKeys.id)
        static let clientConversationId: Column = Column(CodingKeys.clientConversationId)
        static let creatorId: Column = Column(CodingKeys.creatorId)
        static let kind: Column = Column(CodingKeys.kind)
        static let consent: Column = Column(CodingKeys.consent)
        static let createdAt: Column = Column(CodingKeys.createdAt)
        static let name: Column = Column(CodingKeys.name)
        static let description: Column = Column(CodingKeys.description)
        static let imageURLString: Column = Column(CodingKeys.imageURLString)
    }

    let id: String
    let clientConversationId: String // always the same, used for conversation drafts
    let creatorId: String
    let kind: ConversationKind
    let consent: Consent
    let createdAt: Date
    let name: String?
    let description: String?
    let imageURLString: String?

    static let creatorForeignKey: ForeignKey = ForeignKey(["creatorId"], to: ["inboxId"])
    static let localStateForeignKey: ForeignKey = ForeignKey(["conversationId"], to: ["id"])

    static let creator: BelongsToAssociation<DBConversation, Member> = belongsTo(
        Member.self,
        key: "conversationCreator",
        using: creatorForeignKey
    )

    static let creatorProfile: HasOneThroughAssociation<DBConversation, MemberProfile> = hasOne(
        MemberProfile.self,
        through: creator,
        using: Member.profile,
        key: "conversationCreatorProfile"
    )

    private static let _members: HasManyAssociation<DBConversation, DBConversationMember> = hasMany(
        DBConversationMember.self,
        key: "conversationMembers"
    ).order(Column("createdAt").asc)

    private static let members: HasManyThroughAssociation<DBConversation, Member> = hasMany(
        Member.self,
        through: _members,
        using: DBConversationMember.member,
        key: "conversationMembers"
    )

    static let memberProfiles: HasManyThroughAssociation<DBConversation, MemberProfile> = hasMany(
        MemberProfile.self,
        through: _members,
        using: DBConversationMember.memberProfile,
        key: "conversationMemberProfiles"
    )

    static let messages: HasManyAssociation<DBConversation, DBMessage> = hasMany(
        DBMessage.self,
        key: "conversationMessages",
        using: ForeignKey(["id"], to: ["conversationId"])
    ).order(Column("date").desc)

    static let lastMessageRequest: QueryInterfaceRequest<DBMessage> = DBMessage
        .annotated { max($0.date) }
        .group(\.conversationId)

    static let lastMessageCTE: CommonTableExpression<DBMessage> = CommonTableExpression<DBMessage>(
        named: "conversationLastMessage",
        request: lastMessageRequest
    )

    static let localState: HasOneAssociation<DBConversation, ConversationLocalState> = hasOne(
        ConversationLocalState.self,
        key: "conversationLocalState",
        using: localStateForeignKey
    )
}

extension DBConversation {
    private static var draftPrefix: String { "draft-" }

    static func generateDraftConversationId() -> String {
        "\(draftPrefix)\(UUID().uuidString)"
    }

    var isDraft: Bool {
        (id.hasPrefix(Self.draftPrefix) &&
         clientConversationId.hasPrefix(Self.draftPrefix))
    }

    func with(id: String) -> Self {
        .init(
            id: id,
            clientConversationId: clientConversationId,
            creatorId: creatorId,
            kind: kind,
            consent: consent,
            createdAt: createdAt,
            name: name,
            description: description,
            imageURLString: imageURLString
        )
    }

    func with(clientConversationId: String) -> Self {
        .init(
            id: id,
            clientConversationId: clientConversationId,
            creatorId: creatorId,
            kind: kind,
            consent: consent,
            createdAt: createdAt,
            name: name,
            description: description,
            imageURLString: imageURLString
        )
    }

    func with(kind: ConversationKind) -> Self {
        .init(
            id: id,
            clientConversationId: clientConversationId,
            creatorId: creatorId,
            kind: kind,
            consent: consent,
            createdAt: createdAt,
            name: name,
            description: description,
            imageURLString: imageURLString
        )
    }
}

extension DBConversation {
    static func findConversationWith(members ids: [String]) -> SQLRequest<DBConversation>? {
        let sql = """
        SELECT *
        FROM conversation
        WHERE id IN (
            SELECT conversationId
            FROM conversationMember
            WHERE memberId IN (\(ids.map { _ in "?" }.joined(separator: ", ")))
            GROUP BY conversationId
            HAVING COUNT(*) = ?
               AND COUNT(DISTINCT memberId) = ?
        )
        """
        guard let arguments = StatementArguments(ids + [ids.count, ids.count]) else {
            return nil
        }
        return SQLRequest<DBConversation>(sql: sql, arguments: arguments)
    }
}

struct DBConversationDetails: Codable, FetchableRecord, PersistableRecord, Hashable {
    let conversation: DBConversation
    let conversationCreatorProfile: MemberProfile
    let conversationMemberProfiles: [MemberProfile]
    let conversationLastMessage: DBMessage?
    let conversationLocalState: ConversationLocalState
}

struct DBConversationMember: Codable, FetchableRecord, PersistableRecord, Hashable {
    enum Role: Codable, Hashable {
        case member, admin, superAdmin
    }

    enum Consent: Hashable, Codable {
        case allowed, denied, unknown
    }

    let conversationId: String
    let memberId: String
    let role: Role
    let consent: Consent
    let createdAt: Date

    static var databaseTableName: String { "conversation_members" }

    static let memberForeignKey: ForeignKey = ForeignKey(["memberId"], to: ["inboxId"])
    static let conversationForeignKey: ForeignKey = ForeignKey(["conversationId"])

    static let conversation: BelongsToAssociation<DBConversationMember, DBConversation> = belongsTo(
        DBConversation.self,
        using: conversationForeignKey
    )

    static let member: BelongsToAssociation<DBConversationMember, Member> = belongsTo(
        Member.self,
        using: memberForeignKey
    )

    static let memberProfile: HasManyThroughAssociation<DBConversationMember, MemberProfile> = hasMany(
        MemberProfile.self,
        through: member,
        using: Member.profile
    )
}

struct Conversation: Codable, Hashable, Identifiable {
    let id: String
    let creator: Profile
    let createdAt: Date
    let kind: ConversationKind
    let name: String?
    let description: String?
    let members: [Profile]
    let otherMember: Profile?
    let messages: [Message]
    let isPinned: Bool
    let isUnread: Bool
    let isMuted: Bool
    let lastMessage: MessagePreview?
    let imageURL: URL?
    let isDraft: Bool
}

extension Conversation {
    var memberNamesString: String {
        members.map { $0.displayName }
            .filter { !$0.isEmpty }
            .sorted()
            .joined(separator: ", ")
    }

    var membersCountString: String {
        "\(members.count) \(members.count == 1 ? "member" : "members")"
    }
}

struct ConversationLocalState: Codable, FetchableRecord, PersistableRecord, Hashable {
    let conversationId: String
    let isPinned: Bool
    let isUnread: Bool
    let isMuted: Bool

    static let conversationForeignKey: ForeignKey = ForeignKey(["conversationId"], to: ["id"])

    static let conversation: BelongsToAssociation<ConversationLocalState, DBConversation> = belongsTo(
        DBConversation.self,
        using: conversationForeignKey
    )
}
