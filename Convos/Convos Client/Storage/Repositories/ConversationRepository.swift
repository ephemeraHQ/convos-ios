import Combine
import Foundation
import GRDB

protocol ConversationRepositoryProtocol {
    var conversationId: String { get }
    var conversationPublisher: AnyPublisher<Conversation?, Never> { get }
    var conversationWithRolesPublisher: AnyPublisher<(Conversation, [ProfileWithRole])?, Never> { get }

    func fetchConversation() throws -> Conversation?
    func fetchConversationWithRoles() throws -> (Conversation, [ProfileWithRole])?
}

class ConversationRepository: ConversationRepositoryProtocol {
    private let dbReader: any DatabaseReader
    let conversationId: String
    private let messagesRepository: MessagesRepository

    init(conversationId: String, dbReader: any DatabaseReader) {
        self.dbReader = dbReader
        self.conversationId = conversationId
        self.messagesRepository = MessagesRepository(
            dbReader: dbReader,
            conversationId: conversationId
        )
    }

    lazy var conversationPublisher: AnyPublisher<Conversation?, Never> = {
        ValueObservation
            .tracking { [weak self] db in
                guard let self else { return nil }
                return try db.composeConversation(for: conversationId)
            }
            .publisher(in: dbReader)
            .replaceError(with: nil)
            .eraseToAnyPublisher()
    }()

    lazy var conversationWithRolesPublisher: AnyPublisher<(Conversation, [ProfileWithRole])?, Never> = {
        ValueObservation
            .tracking { [weak self] db in
                guard let self else { return nil }
                return try db.composeConversationWithRoles(for: conversationId)
            }
            .publisher(in: dbReader)
            .replaceError(with: nil)
            .eraseToAnyPublisher()
    }()

    func fetchConversation() throws -> Conversation? {
        try dbReader.read { [weak self] db in
            guard let self else { return nil }
            return try db.composeConversation(for: conversationId)
        }
    }

    func fetchConversationWithRoles() throws -> (Conversation, [ProfileWithRole])? {
        try dbReader.read { [weak self] db in
            guard let self else { return nil }
            return try db.composeConversationWithRoles(for: conversationId)
        }
    }
}

fileprivate extension Database {
    func composeConversation(for conversationId: String) throws -> Conversation? {
        guard let currentUser = try currentUser() else {
            throw CurrentSessionError.missingCurrentUser
        }

        guard let dbConversation = try DBConversation
            .filter(DBConversation.Columns.id == conversationId)
            .including(required: DBConversation.creatorProfile)
            .including(required: DBConversation.localState)
            .including(all: DBConversation.memberProfiles)
            .asRequest(of: DBConversationDetails.self)
            .fetchOne(self) else {
            return nil
        }

        return dbConversation.hydrateConversation(
            currentUser: currentUser
        )
    }

    func composeConversationWithRoles(for conversationId: String) throws -> (Conversation, [ProfileWithRole])? {
        let startTime = CFAbsoluteTimeGetCurrent()
        Logger.info("⏱️ Starting composeConversationWithRoles for: \(conversationId)")

        // Get current user for proper profile hydration
        guard let currentUser = try currentUser() else {
            Logger.error("❌ No current user found")
            throw CurrentSessionError.missingCurrentUser
        }

        // First get the conversation normally
        guard let conversation = try composeConversation(for: conversationId) else {
            Logger.info("❌ No conversation found for id: \(conversationId)")
            return nil
        }

        let conversationLoadTime = CFAbsoluteTimeGetCurrent()
        let loadTime = String(format: "%.3f", conversationLoadTime - startTime)
        Logger.info("⏱️ Conversation load took: \(loadTime)s")
        Logger.info("📊 Conversation has \(conversation.members.count) members, kind: \(conversation.kind)")

        // Fetch conversation members with a single optimized query
        let conversationMembers = try DBConversationMember
            .filter(DBConversationMember.Columns.conversationId == conversationId)
            .fetchAll(self)

        let membersLoadTime = CFAbsoluteTimeGetCurrent()
        let membersTime = String(format: "%.3f", membersLoadTime - conversationLoadTime)
        Logger.info("⏱️ Members load took: \(membersTime)s")
        Logger.info("📊 Found \(conversationMembers.count) DBConversationMembers")

        // Create a dictionary for O(1) member role lookups instead of O(n) linear search
        let memberRoleMap: [String: MemberRole] = Dictionary(
            conversationMembers.compactMap { member in
                let memberRole: MemberRole
                switch member.role {
                case .member: memberRole = .member
                case .admin: memberRole = .admin
                case .superAdmin: memberRole = .superAdmin
                }
                Logger.info("📊 Member \(member.memberId) has role: \(memberRole)")
                return (member.memberId, memberRole)
            },
            uniquingKeysWith: { first, _ in first }
        )

        // Combine profiles with roles efficiently
        let allMembers = conversation.withCurrentUserIncluded().members
        Logger.info("📊 Processing \(allMembers.count) total members")

        let membersWithRoles: [ProfileWithRole] = allMembers.map { profile in
            // Use current user's actual profile if this is the current user
            let actualProfile: Profile
            if profile.id == currentUser.inboxId || profile.id == "current" {
                actualProfile = currentUser.profile
            } else {
                actualProfile = profile
            }

            // O(1) lookup instead of O(n) linear search
            let memberRole = memberRoleMap[actualProfile.id] ??
                            memberRoleMap[currentUser.inboxId] ??
                            .member

            Logger.info("📊 ProfileWithRole: \(actualProfile.displayName) -> \(memberRole)")
            return ProfileWithRole(profile: actualProfile, role: memberRole)
        }

        let totalTime = CFAbsoluteTimeGetCurrent()
        let duration = String(format: "%.3f", totalTime - startTime)
        Logger.info("⏱️ Total composeConversationWithRoles took: \(duration)s")
        Logger.info("📊 Processed \(membersWithRoles.count) members total")
        Logger.info("✅ Returning \(membersWithRoles.count) ProfileWithRole objects")

        return (conversation, membersWithRoles)
    }
}
