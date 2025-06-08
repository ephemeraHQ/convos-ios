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

    private let conversation: Conversation = .mock()

    func fetchConversation() throws -> Conversation? {
        conversation
    }
}
