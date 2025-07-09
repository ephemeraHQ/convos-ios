import Combine
import Foundation
import GRDB

protocol DraftConversationRepositoryProtocol: ConversationRepositoryProtocol {
    var membersPublisher: AnyPublisher<[Profile], Never> { get }
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

    lazy var membersPublisher: AnyPublisher<[Profile], Never> = {
        let draftConversationId = writer.draftConversationId
        return ValueObservation
            .tracking { [weak self] db in
                guard let self else { return [] }
                guard let currentUser = try db.currentUser() else {
                    return []
                }
                guard let dbConversation = try DBConversation
                    .filter(Column("clientConversationId") == draftConversationId)
                    .including(required: DBConversation.creatorProfile)
                    .including(required: DBConversation.localState)
                    .including(all: DBConversation.memberProfiles)
                    .asRequest(of: DBConversationDetails.self)
                    .fetchOne(db) else {
                    return []
                }
                return dbConversation
                    .hydrateConversation(currentUser: currentUser)
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

    lazy var conversationWithRolesPublisher: AnyPublisher<(Conversation, [ProfileWithRole])?, Never> = {
        writer.conversationIdPublisher
            .removeDuplicates()
            .map { [weak self] conversationId -> AnyPublisher<(Conversation, [ProfileWithRole])?, Never> in
                guard let self else {
                    return Just(nil as (Conversation, [ProfileWithRole])?).eraseToAnyPublisher()
                }

                return ValueObservation
                    .tracking { [weak self] db in
                        guard let self else { return nil }
                        return try db.composeConversation(for: conversationId)
                    }
                    .publisher(in: dbReader)
                    .replaceError(with: nil)
                    .map { (conversation: Conversation?) -> (Conversation, [ProfileWithRole])? in
                        guard let conversation = conversation else { return nil }
                        // For draft conversations, all members have .member role
                        let membersWithRoles = conversation.withCurrentUserIncluded().members.map { profile in
                            ProfileWithRole(profile: profile, role: .member)
                        }
                        return (conversation, membersWithRoles)
                    }
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

    func fetchConversationWithRoles() throws -> (Conversation, [ProfileWithRole])? {
        guard let conversation = try fetchConversation() else { return nil }

        // For draft conversations, all members have .member role since no roles are established yet
        let membersWithRoles = conversation.withCurrentUserIncluded().members.map { profile in
            ProfileWithRole(profile: profile, role: .member)
        }

        return (conversation, membersWithRoles)
    }
}

fileprivate extension Database {
    func composeConversation(for conversationId: String) throws -> Conversation? {
        guard let currentUser = try currentUser() else {
            throw CurrentSessionError.missingCurrentUser
        }

        let lastMessage = DBConversation.association(
            to: DBConversation.lastMessageCTE,
            on: { conversation, lastMessage in
                conversation.clientConversationId == lastMessage.conversationId
            }).forKey("conversationLastMessage")
            .order(\.date.desc)
        guard let dbConversation = try DBConversation
            .filter(Column("clientConversationId") == conversationId)
            .including(required: DBConversation.creatorProfile)
            .including(required: DBConversation.localState)
            .including(all: DBConversation.memberProfiles)
            .with(DBConversation.lastMessageCTE)
            .including(optional: lastMessage)
            .asRequest(of: DBConversationDetails.self)
            .fetchOne(self) else {
            return nil
        }

        return dbConversation.hydrateConversation(
            currentUser: currentUser
        )
    }
}
