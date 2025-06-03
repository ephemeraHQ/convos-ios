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

    func fetchConversation() throws -> Conversation? {
        conversation
    }
}

class MockDraftConversationRepository: DraftConversationRepositoryProtocol {
    var messagesRepositoryPublisher: AnyPublisher<any MessagesRepositoryProtocol, Never> {
        Just(MockMessagesRepository(conversation: conversation)).eraseToAnyPublisher()
    }

    var conversationPublisher: AnyPublisher<Conversation?, Never> {
        Just(conversation).eraseToAnyPublisher()
    }

    func subscribe(to writer: any DraftConversationWriterProtocol) {
    }

    private let conversation: Conversation = .mock()

    func fetchConversation() throws -> Conversation? {
        conversation
    }
}
