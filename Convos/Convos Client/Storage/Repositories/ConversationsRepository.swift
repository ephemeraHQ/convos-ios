import Combine
import Foundation
import GRDB

protocol ConversationsRepositoryProtocol {
    var conversationsPublisher: AnyPublisher<[Conversation], Never> { get }
    func fetchAll() throws -> [Conversation]
}

final class ConversationsRepository: ConversationsRepositoryProtocol {
    private let dbReader: any DatabaseReader
    private let consent: [Consent]

    lazy var conversationsPublisher: AnyPublisher<[Conversation], Never> = {
        ValueObservation
            .tracking { [weak self] db in
                guard let self else { return [] }
                return try db.composeAllConversations(consent: consent)
            }
            .publisher(in: dbReader)
            .replaceError(with: [])
            .eraseToAnyPublisher()
    }()

    init(dbReader: any DatabaseReader, consent: [Consent]) {
        self.dbReader = dbReader
        self.consent = consent
    }

    func fetchAll() throws -> [Conversation] {
        try dbReader.read { [weak self] db in
            guard let self else { return [] }
            return try db.composeAllConversations(consent: consent)
        }
    }
}

extension Array where Element == DBConversationDetails {
    func composeConversations(from database: Database) throws -> [Conversation] {
        let dbConversations: [DBConversationDetails] = self

        let conversations: [Conversation] = dbConversations
            .compactMap { dbConversationDetails in
            dbConversationDetails.hydrateConversation()
        }

        return conversations
    }
}

fileprivate extension Database {
    func composeAllConversations(consent: [Consent]) throws -> [Conversation] {
        let lastMessage = DBConversation.association(
            to: DBConversation.lastMessageCTE,
            on: { conversation, lastMessage in
                conversation.id == lastMessage.conversationId
            }).forKey("conversationLastMessage")
            .order(\.date.desc)
        let dbConversationDetails = try DBConversation
            .filter(!Column("id").like("draft-%"))
            .filter(consent.contains(DBConversation.Columns.consent))
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
