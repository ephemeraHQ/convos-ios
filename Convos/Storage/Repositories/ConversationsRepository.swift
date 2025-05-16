import Combine
import Foundation
import GRDB

protocol ConversationsRepositoryProtocol {
    func fetchAll() throws -> [Conversation]
    func conversationsPublisher() -> AnyPublisher<[Conversation], Never>
}

final class ConversationsRepository: ConversationsRepositoryProtocol {
    private let dbReader: any DatabaseReader

    init(dbReader: any DatabaseReader) {
        self.dbReader = dbReader
    }

    func fetchAll() throws -> [Conversation] {
        try dbReader.read { db in
            return try Conversation.fetchAll(db)
        }
    }

    func conversationsPublisher() -> AnyPublisher<[Conversation], Never> {
        ValueObservation
            .tracking { db in
                return try Conversation
                    .fetchAll(db)
            }
            .publisher(in: dbReader)
            .replaceError(with: [])
            .eraseToAnyPublisher()
    }
}
