import Combine
import Foundation
import GRDB

public protocol ConversationRepositoryProtocol {
    var conversationId: String { get }
    var conversationPublisher: AnyPublisher<Conversation?, Never> { get }

    func fetchConversation() throws -> Conversation?
}

class ConversationRepository: ConversationRepositoryProtocol {
    private let dbReader: any DatabaseReader
    let conversationId: String
    private let messagesRepository: MessagesRepository

    init(conversationId: String, dbReader: any DatabaseReader) {
        self.dbReader = dbReader
        self.conversationId = conversationId
        self.messagesRepository = MessagesRepository(
            dbReader: dbReader,
            conversationId: conversationId
        )
    }

    lazy var conversationPublisher: AnyPublisher<Conversation?, Never> = {
        ValueObservation
            .tracking { [weak self] db in
                guard let self else { return nil }
                return try db.composeConversation(for: conversationId)
            }
            .publisher(in: dbReader)
            .replaceError(with: nil)
            .eraseToAnyPublisher()
    }()

    func fetchConversation() throws -> Conversation? {
        try dbReader.read { [weak self] db in
            guard let self else { return nil }
            return try db.composeConversation(for: conversationId)
        }
    }
}

fileprivate extension Database {
    func composeConversation(for conversationId: String) throws -> Conversation? {
        guard let dbConversation = try DBConversation
            .filter(DBConversation.Columns.id == conversationId)
            .detailedConversationQuery()
            .fetchOne(self) else {
            return nil
        }

        return dbConversation.hydrateConversation()
    }
}
