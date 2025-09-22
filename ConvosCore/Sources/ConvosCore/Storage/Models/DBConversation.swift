import Foundation
import GRDB

// MARK: - DBConversation

public struct DBConversation: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable {
    public static var databaseTableName: String = "conversation"

    public enum Columns {
        static let id: Column = Column(CodingKeys.id)
        static let inboxId: Column = Column(CodingKeys.inboxId)
        static let clientConversationId: Column = Column(CodingKeys.clientConversationId)
        static let creatorId: Column = Column(CodingKeys.creatorId)
        static let kind: Column = Column(CodingKeys.kind)
        static let consent: Column = Column(CodingKeys.consent)
        static let createdAt: Column = Column(CodingKeys.createdAt)
        static let name: Column = Column(CodingKeys.name)
        static let description: Column = Column(CodingKeys.description)
        static let imageURLString: Column = Column(CodingKeys.imageURLString)
    }

    public let id: String
    public let inboxId: String
    public let clientConversationId: String // used for conversation drafts
    public let creatorId: String
    public let kind: ConversationKind
    public let consent: Consent
    public let createdAt: Date
    public let name: String?
    public let description: String?
    public let imageURLString: String?

    static let creatorForeignKey: ForeignKey = ForeignKey(
        [Columns.creatorId],
        to: [DBConversationMember.Columns.inboxId]
    )
    static let inboxMemberKey: ForeignKey = ForeignKey(
        [Columns.inboxId],
        to: [DBConversationMember.Columns.inboxId]
    )
    static let localStateForeignKey: ForeignKey = ForeignKey(["conversationId"], to: ["id"])
    static let inviteForeignKey: ForeignKey = ForeignKey(["conversationId"], to: ["id"])

    // The invite created by the current inbox member (the user viewing this conversation)
    static let invite: HasOneThroughAssociation<DBConversation, DBInvite> = hasOne(
        DBInvite.self,
        through: inboxMember,
        using: DBConversationMember.invite,
        key: "conversationInvite"
    )

    // The invite created by the conversation creator
    static let creatorInvite: HasOneThroughAssociation<DBConversation, DBInvite> = hasOne(
        DBInvite.self,
        through: creator,
        using: DBConversationMember.invite,
        key: "conversationCreatorInvite"
    )

    static let creator: BelongsToAssociation<DBConversation, DBConversationMember> = belongsTo(
        DBConversationMember.self,
        key: "conversationCreator",
        using: creatorForeignKey
    )

    // the member whos inbox this is
    static let inboxMember: BelongsToAssociation<DBConversation, DBConversationMember> = belongsTo(
        DBConversationMember.self,
        key: "conversationInboxMember",
        using: inboxMemberKey
    )

    static let creatorProfile: HasOneThroughAssociation<DBConversation, MemberProfile> = hasOne(
        MemberProfile.self,
        through: creator,
        using: DBConversationMember.memberProfile,
        key: "conversationCreatorProfile"
    )

    static let _members: HasManyAssociation<DBConversation, DBConversationMember> = hasMany(
        DBConversationMember.self,
        key: "conversationMembers"
    ).order(Column("createdAt").asc)

    static let members: HasManyThroughAssociation<DBConversation, Member> = hasMany(
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
    ).order(DBMessage.Columns.dateNs.desc)

    static let lastMessageRequest: QueryInterfaceRequest<DBMessage> = DBMessage
        .filter(DBMessage.Columns.contentType != MessageContentType.update.rawValue)
        .annotated { max($0.dateNs) }
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

// MARK: - DBConversation Extensions

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
            inboxId: inboxId,
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
            inboxId: inboxId,
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
            inboxId: inboxId,
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

    func with(consent: Consent) -> Self {
        .init(
            id: id,
            inboxId: inboxId,
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

    // MARK: - Group Conversation Properties

    func with(name: String?) -> Self {
        .init(
            id: id,
            inboxId: inboxId,
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

    func with(description: String?) -> Self {
        .init(
            id: id,
            inboxId: inboxId,
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

    func with(imageURLString: String?) -> Self {
        .init(
            id: id,
            inboxId: inboxId,
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
    static func findConversationWith(members ids: [String], inboxId: String, db: Database) throws -> DBConversation? {
        let ids = Array(Set<String>(ids))
        guard !ids.isEmpty else { return nil }
        let count = ids.count

        // Find candidate conversation IDs
        let placeholders = databaseQuestionMarks(count: count)
        let sql = """
        SELECT conversationId
        FROM \(DBConversationMember.databaseTableName)
        WHERE memberId IN (\(placeholders))
          AND conversationId NOT LIKE 'draft-%'
        GROUP BY conversationId
        HAVING COUNT(DISTINCT memberId) = :count
        """
        var arguments = StatementArguments()
        for id in ids {
            arguments += [id]
        }
        arguments += ["count": count]

        let candidateIds = try String.fetchAll(db, sql: sql, arguments: arguments)

        // For each candidate, check if the set of member IDs matches exactly
        for conversationId in candidateIds {
            let memberIds = try String.fetchAll(
                db,
                sql: "SELECT memberId FROM \(DBConversationMember.databaseTableName) WHERE conversationId = ?",
                arguments: [conversationId]
            )
            if Set(memberIds) == Set(ids),
               let conversation = try DBConversation
                .fetchOne(db, key: conversationId),
               conversation.inboxId == inboxId {
                return conversation
            }
        }
        return nil
    }
}
