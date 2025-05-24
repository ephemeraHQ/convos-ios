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

    func messagesPublisher() -> AnyPublisher<[AnyMessage], Never> {
        Just([]).eraseToAnyPublisher()
    }
}
