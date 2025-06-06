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
            try db.composeAllConversations()
        }
    }

    func conversationsPublisher() -> AnyPublisher<[Conversation], Never> {
        ValueObservation
            .tracking { db in
                try db.composeAllConversations()
            }
            .publisher(in: dbReader)
            .replaceError(with: [])
            .eraseToAnyPublisher()
    }
}

extension Array where Element == DBConversationDetails {
    func composeConversations(from database: Database) throws -> [Conversation] {
        let dbConversations: [DBConversationDetails] = self

        guard let currentUser = try database.currentUser() else {
            return []
        }

        let conversations: [Conversation] = dbConversations
            .filter { !$0.conversation.isDraft }
            .compactMap { dbConversationDetails in
            dbConversationDetails.hydrateConversation(
                currentUser: currentUser
            )
        }

        return conversations
    }
}

fileprivate extension Database {
    func composeAllConversations() throws -> [Conversation] {
        let lastMessage = DBConversation.association(
            to: DBConversation.lastMessageCTE,
            on: { conversation, lastMessage in
                conversation.id == lastMessage.conversationId
            }).forKey("conversationLastMessage")
            .order(\.date.desc)
        let dbConversationDetails = try DBConversation
            .filter(DBConversation.Columns.consent == DBConversation.Consent.allowed.rawValue)
            .including(required: DBConversation.creatorProfile)
            .including(required: DBConversation.localState)
            .including(all: DBConversation.memberProfiles)
            .with(DBConversation.lastMessageCTE)
            .including(optional: lastMessage)
            .asRequest(of: DBConversationDetails.self)
            .fetchAll(self)

        return try dbConversationDetails.composeConversations(from: self)
    }
}
