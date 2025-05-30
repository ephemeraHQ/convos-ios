import Combine
import Foundation

class MockConversationRepository: ConversationRepositoryProtocol {
    var messagesRepositoryPublisher: AnyPublisher<any MessagesRepositoryProtocol, Never> {
        Just(MockMessagesRepository(conversation: conversation)).eraseToAnyPublisher()
    }

    var conversationPublisher: AnyPublisher<Conversation?, Never> {
        Just(conversation).eraseToAnyPublisher()
    }

    private let conversation: Conversation = .mock()
}

class MockDraftConversationRepository: DraftConversationRepositoryProtocol {
    var selectedConversationId: String?

    var messagesRepositoryPublisher: AnyPublisher<any MessagesRepositoryProtocol, Never> {
        Just(MockMessagesRepository(conversation: conversation)).eraseToAnyPublisher()
    }

    var conversationPublisher: AnyPublisher<Conversation?, Never> {
        Just(conversation).eraseToAnyPublisher()
    }

    private let conversation: Conversation = .mock()
}
