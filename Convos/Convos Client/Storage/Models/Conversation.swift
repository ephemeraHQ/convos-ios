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

    enum Columns {
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

    let id: String
    let inboxId: String
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
}

extension DBConversation {
    static func findConversationWith(members ids: [String], db: Database) throws -> DBConversation? {
        let ids = Array(Set<String>(ids))
        guard !ids.isEmpty else { return nil }
        let count = ids.count

        // Step 1: Find candidate conversation IDs
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

        // Step 2: For each candidate, check if the set of member IDs matches exactly
        for conversationId in candidateIds {
            let memberIds = try String.fetchAll(
                db,
                sql: "SELECT memberId FROM \(DBConversationMember.databaseTableName) WHERE conversationId = ?",
                arguments: [conversationId]
            )
            if Set(memberIds) == Set(ids) {
                // Found exact match
                return try DBConversation.fetchOne(db, key: conversationId)
            }
        }
        return nil
    }
}

struct DBConversationDetails: Codable, FetchableRecord, PersistableRecord, Hashable {
    let conversation: DBConversation
    let conversationCreatorProfile: MemberProfile
    let conversationMemberProfiles: [MemberProfile]
    let conversationLastMessage: DBMessage?
    let conversationLocalState: ConversationLocalState
}

extension Array where Element == Consent {
    static var all: [Consent] {
        Consent.allCases
    }

    static var allowed: [Consent] {
        [.allowed]
    }

    static var denied: [Consent] {
        [.denied]
    }

    static var securityLine: [Consent] {
        [.unknown]
    }
}

enum Consent: String, Codable, Hashable, SQLExpressible, CaseIterable {
    case allowed, denied, unknown
}

struct DBConversationMember: Codable, FetchableRecord, PersistableRecord, Hashable {
    enum Role: String, Codable, Hashable {
        case member, admin, superAdmin = "super_admin"
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

    static let memberProfile: HasOneThroughAssociation<DBConversationMember, MemberProfile> = hasOne(
        MemberProfile.self,
        through: member,
        using: Member.profile
    )
}

struct Conversation: Codable, Hashable, Identifiable {
    let id: String
    let inboxId: String
    let creator: Profile
    let createdAt: Date
    let consent: Consent
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
        members.formattedNamesString
    }

    var membersCountString: String {
        "\(members.count) \(members.count == 1 ? "person" : "people")"
    }
}

struct ConversationLocalState: Codable, FetchableRecord, PersistableRecord, Hashable {
    let conversationId: String
    let isPinned: Bool
    let isUnread: Bool
    let isUnreadUpdatedAt: Date
    let isMuted: Bool

    static let conversationForeignKey: ForeignKey = ForeignKey(["conversationId"], to: ["id"])

    static let conversation: BelongsToAssociation<ConversationLocalState, DBConversation> = belongsTo(
        DBConversation.self,
        using: conversationForeignKey
    )
}

extension ConversationLocalState {
    func with(isUnread: Bool) -> Self {
        .init(
            conversationId: conversationId,
            isPinned: isPinned,
            isUnread: isUnread,
            isUnreadUpdatedAt: !isUnread ? Date() : (isUnread != self.isUnread ? Date() : isUnreadUpdatedAt),
            isMuted: isMuted
        )
    }
    func with(isPinned: Bool) -> Self {
        .init(
            conversationId: conversationId,
            isPinned: isPinned,
            isUnread: isUnread,
            isUnreadUpdatedAt: isUnreadUpdatedAt,
            isMuted: isMuted
        )
    }
    func with(isMuted: Bool) -> Self {
        .init(
            conversationId: conversationId,
            isPinned: isPinned,
            isUnread: isUnread,
            isUnreadUpdatedAt: isUnreadUpdatedAt,
            isMuted: isMuted
        )
    }
}

extension Array where Element == Profile {
    var formattedNamesString: String {
        let displayNames = self.map { $0.displayName }
            .filter { !$0.isEmpty }
            .sorted()

        switch displayNames.count {
        case 0:
            return ""
        case 1:
            return displayNames[0]
        case 2:
            return displayNames.joined(separator: " & ")
        default:
            let allButLast = displayNames.dropLast().joined(separator: ", ")
            let last = displayNames.last ?? ""
            return "\(allButLast) and \(last)"
        }
    }
}
