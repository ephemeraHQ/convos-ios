import Combine
import Foundation
import GRDB

protocol ConversationRepositoryProtocol {
    func conversationPublisher() -> AnyPublisher<Conversation?, Never>
}

class ConversationRepository: ConversationRepositoryProtocol {
    private let dbReader: any DatabaseReader
    private let conversationId: String

    init(conversationId: String, dbReader: any DatabaseReader) {
        self.dbReader = dbReader
        self.conversationId = conversationId
    }

    func conversationPublisher() -> AnyPublisher<Conversation?, Never> {
        ValueObservation
            .tracking { [weak self] db in
                guard let self else { return nil }

                guard let currentUser = try db.currentUser() else {
                    return nil
                }

                guard let dbConversation = try DBConversationDetails.fetchOne(db, key: conversationId) else {
                    return nil
                }

                return dbConversation.hydrateConversation(
                    currentUser: currentUser
                )
            }
            .publisher(in: dbReader)
            .replaceError(with: nil)
            .eraseToAnyPublisher()
    }
}
