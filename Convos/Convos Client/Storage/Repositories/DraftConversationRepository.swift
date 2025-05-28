import Combine
import Foundation
import GRDB

extension Conversation {
    static var draftPrimaryKey: String {
        "draft"
    }
}

class DraftConversationRepository: ConversationRepositoryProtocol {
    private let dbReader: any DatabaseReader
    private let conversationId: String

    init(dbReader: any DatabaseReader) {
        self.dbReader = dbReader
        self.conversationId = Conversation.draftPrimaryKey
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
