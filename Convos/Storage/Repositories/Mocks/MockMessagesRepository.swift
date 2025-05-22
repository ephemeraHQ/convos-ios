import Combine
import Foundation

class MockMessagesRepository: MessagesRepositoryProtocol {
    func fetchAll() throws -> [AnyMessage] {
        return []
    }

    func messagesPublisher() -> AnyPublisher<[AnyMessage], Never> {
        Just([]).eraseToAnyPublisher()
    }
}
