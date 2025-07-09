import Combine
import Foundation

class MockConversationRepository: ConversationRepositoryProtocol {
    var conversationPublisher: AnyPublisher<Conversation?, Never> {
        Just(conversation).eraseToAnyPublisher()
    }

    var conversationId: String {
        conversation.id
    }

    private let conversation: Conversation = .mock()

    func fetchConversation() throws -> Conversation? {
        conversation
    }

    func fetchConversationWithRoles() throws -> (Conversation, [ProfileWithRole])? {
        // Mock implementation: assign random roles to members
        let membersWithRoles = conversation.withCurrentUserIncluded().members.map { profile in
            let role: MemberRole = [.member, .admin, .superAdmin].randomElement() ?? .member
            return ProfileWithRole(profile: profile, role: role)
        }

        return (conversation, membersWithRoles)
    }
}

class MockDraftConversationRepository: DraftConversationRepositoryProtocol {
    var conversationId: String {
        conversation.id
    }

    var membersPublisher: AnyPublisher<[Profile], Never> {
        Just([]).eraseToAnyPublisher()
    }
    var messagesRepository: any MessagesRepositoryProtocol {
        MockMessagesRepository(conversation: conversation)
    }

    var conversationPublisher: AnyPublisher<Conversation?, Never> {
        Just(conversation).eraseToAnyPublisher()
    }

    private let conversation: Conversation = .mock(id: "draft-123")

    func fetchConversation() throws -> Conversation? {
        conversation
    }

    func fetchConversationWithRoles() throws -> (Conversation, [ProfileWithRole])? {
        // For draft conversations, all members have .member role
        let membersWithRoles = conversation.withCurrentUserIncluded().members.map { profile in
            ProfileWithRole(profile: profile, role: .member)
        }

        return (conversation, membersWithRoles)
    }
}
