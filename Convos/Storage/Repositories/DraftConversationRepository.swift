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

                guard let dbConversation = try DBConversation.fetchOne(db, key: conversationId) else {
                    return nil
                }

                return try [dbConversation].composeConversations(from: db).first
            }
            .publisher(in: dbReader)
            .replaceError(with: nil)
            .eraseToAnyPublisher()
    }
}
