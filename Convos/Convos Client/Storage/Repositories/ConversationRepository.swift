import Combine
import Foundation
import GRDB

protocol ConversationRepositoryProtocol {
    var conversationId: String { get }
    var conversationPublisher: AnyPublisher<Conversation?, Never> { get }

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
        // Get current user for proper profile hydration
        guard let currentUser = try currentUser() else {
            throw CurrentSessionError.missingCurrentUser
        }

        // First get the conversation normally
        guard let conversation = try composeConversation(for: conversationId) else {
            return nil
        }

        // Then fetch just the conversation members (without associations to avoid conflicts)
        let conversationMembers = try DBConversationMember
            .filter(DBConversationMember.Columns.conversationId == conversationId)
            .fetchAll(self)

        // Combine profiles with roles, ensuring current user gets their proper profile
        let allMembers = conversation.withCurrentUserIncluded().members
        let membersWithRoles: [ProfileWithRole] = allMembers.map { profile in
            // Use current user's actual profile if this is the current user
            let actualProfile: Profile
            if profile.id == currentUser.inboxId || profile.id == "current" {
                actualProfile = currentUser.profile
            } else {
                actualProfile = profile
            }

            // Find the corresponding DBConversationMember to get the role
            let conversationMember = conversationMembers.first(where: { member in
                member.memberId == actualProfile.id ||
                (actualProfile.id == currentUser.inboxId && member.memberId == currentUser.inboxId)
            })

            // Convert DBConversationMember.Role to MemberRole
            let memberRole: MemberRole
            if let conversationMember = conversationMember {
                switch conversationMember.role {
                case .member:
                    memberRole = .member
                case .admin:
                    memberRole = .admin
                case .superAdmin:
                    memberRole = .superAdmin
                }
            } else {
                // Fallback to member role if not found
                memberRole = .member
            }

            return ProfileWithRole(profile: actualProfile, role: memberRole)
        }

        return (conversation, membersWithRoles)
    }
}
