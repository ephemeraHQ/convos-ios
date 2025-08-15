import Combine
import Foundation

class MockMessagesRepository: MessagesRepositoryProtocol {
    public let conversation: Conversation

    init(conversation: Conversation) {
        self.conversation = conversation
    }

    public func fetchAll() throws -> [AnyMessage] {
        return []
    }

    public var conversationMessagesPublisher: AnyPublisher<ConversationMessages, Never> {
        Just((conversation.id, [])).eraseToAnyPublisher()
    }
}
