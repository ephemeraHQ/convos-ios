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

    let conversationsPublisher: AnyPublisher<[Conversation], Never>

    init(dbReader: any DatabaseReader, consent: [Consent]) {
        self.dbReader = dbReader
        self.consent = consent
        self.conversationsPublisher = ValueObservation
            .tracking { db in
                try db.composeAllConversations(consent: consent)
            }
            .publisher(in: dbReader)
            .replaceError(with: [])
            .eraseToAnyPublisher()
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
        let dbConversationDetails = try DBConversation
            .filter(!Column("id").like("draft-%"))
            .filter(consent.contains(DBConversation.Columns.consent))
            .detailedConversationQuery()
            .fetchAll(self)
        return try dbConversationDetails.composeConversations(from: self)
    }
}

extension QueryInterfaceRequest where RowDecoder == DBConversation {
    func detailedConversationQuery() -> QueryInterfaceRequest<DBConversationDetails> {
        let lastMessage = DBConversation.association(
            to: DBConversation.lastMessageCTE,
            on: { conversation, lastMessage in
                conversation.id == lastMessage.conversationId
            }
        ).forKey("conversationLastMessage")
         .order(\.date.desc)

        return self
            .including(
                required: DBConversation.creator
                    .forKey("conversationCreator")
                    .select([DBConversationMember.Columns.role])
                    .including(required: DBConversationMember.memberProfile)
            )
            .including(required: DBConversation.localState)
            .with(DBConversation.lastMessageCTE)
            .including(optional: lastMessage)
            .including(
                all: DBConversation._members
                    .forKey("conversationMembers")
                    .select([DBConversationMember.Columns.role])
                    .including(required: DBConversationMember.memberProfile)
            )
            .group(Column("id"))
            .asRequest(of: DBConversationDetails.self)
    }
}
