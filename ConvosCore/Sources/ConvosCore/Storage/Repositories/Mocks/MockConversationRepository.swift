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
}

class MockDraftConversationRepository: DraftConversationRepositoryProtocol {
    var inviteRepository: any InviteRepositoryProtocol {
        MockInviteRepository()
    }

    var conversationId: String {
        conversation.id
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
}
