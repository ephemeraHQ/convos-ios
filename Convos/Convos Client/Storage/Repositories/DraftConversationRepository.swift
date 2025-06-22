import Combine
import Foundation
import GRDB

protocol DraftConversationRepositoryProtocol: ConversationRepositoryProtocol {
    var membersPublisher: AnyPublisher<[ConversationMember], Never> { get }
    var messagesRepository: any MessagesRepositoryProtocol { get }
}

class DraftConversationRepository: DraftConversationRepositoryProtocol {
    private let dbReader: any DatabaseReader
    private let writer: any DraftConversationWriterProtocol
    let messagesRepository: any MessagesRepositoryProtocol

    var conversationId: String {
        writer.conversationId
    }

    init(dbReader: any DatabaseReader, writer: any DraftConversationWriterProtocol) {
        self.dbReader = dbReader
        self.writer = writer
        messagesRepository = MessagesRepository(
            dbReader: dbReader,
            conversationId: writer.conversationId,
            conversationIdPublisher: writer.conversationIdPublisher
        )
    }

    lazy var membersPublisher: AnyPublisher<[ConversationMember], Never> = {
        let draftConversationId = writer.draftConversationId
        return ValueObservation
            .tracking { [weak self] db in
                guard let self else { return [] }
                guard let dbConversation = try DBConversation
                    .filter(Column("clientConversationId") == draftConversationId)
                    .detailedConversationQuery()
                    .fetchOne(db) else {
                    return []
                }
                return dbConversation
                    .hydrateConversation()
                    .members
            }
            .publisher(in: dbReader)
            .replaceError(with: [])
            .eraseToAnyPublisher()
    }()

    lazy var conversationPublisher: AnyPublisher<Conversation?, Never> = {
        writer.conversationIdPublisher
            .removeDuplicates()
            .map { [weak self] conversationId -> AnyPublisher<Conversation?, Never> in
                guard let self else {
                    return Just(nil).eraseToAnyPublisher()
                }

                return ValueObservation
                    .tracking { [weak self] db in
                        guard let self else { return nil }
                        return try db.composeConversation(for: conversationId)
                    }
                    .publisher(in: dbReader)
                    .replaceError(with: nil)
                    .eraseToAnyPublisher()
            }
            .switchToLatest()
            .eraseToAnyPublisher()
    }()

    func fetchConversation() throws -> Conversation? {
        try dbReader.read { [weak self] db in
            guard let self else { return nil }
            return try db.composeConversation(for: writer.conversationId)
        }
    }
}

fileprivate extension Database {
    func composeConversation(for conversationId: String) throws -> Conversation? {
        guard let dbConversation = try DBConversation
            .filter(Column("clientConversationId") == conversationId)
            .detailedConversationQuery()
            .fetchOne(self) else {
            return nil
        }

        return dbConversation.hydrateConversation()
    }
}
