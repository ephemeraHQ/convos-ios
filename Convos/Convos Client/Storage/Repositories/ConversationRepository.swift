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
                    throw CurrentSessionError.missingCurrentUser
                }

                guard let dbConversation = try DBConversation
                    .filter(Column("id") == self.conversationId)
                    .including(required: DBConversation.creatorProfile)
                    .including(required: DBConversation.localState)
                    .including(all: DBConversation.memberProfiles)
                    .asRequest(of: DBConversationDetails.self)
                    .fetchOne(db) else {
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
