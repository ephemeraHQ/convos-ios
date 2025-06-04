import Combine
import Foundation

class MockMessagesRepository: MessagesRepositoryProtocol {
    let conversation: Conversation

    init(conversation: Conversation) {
        self.conversation = conversation
    }

    func fetchAll() throws -> [AnyMessage] {
        return []
    }

    var conversationMessagesPublisher: AnyPublisher<ConversationMessages, Never> {
        Just((conversation.id, [])).eraseToAnyPublisher()
    }
}
