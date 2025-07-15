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
