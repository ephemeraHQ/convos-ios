import Combine
import Foundation

class MockConversationRepository: ConversationRepositoryProtocol {
    private let conversation: Conversation = .mock()

    func conversationPublisher() -> AnyPublisher<Conversation?, Never> {
        Just(conversation).eraseToAnyPublisher()
    }
}

class MockDraftConversationRepository: ConversationRepositoryProtocol {
    private let conversation: Conversation = .draft()

    func conversationPublisher() -> AnyPublisher<Conversation?, Never> {
        Just(conversation).eraseToAnyPublisher()
    }
}
