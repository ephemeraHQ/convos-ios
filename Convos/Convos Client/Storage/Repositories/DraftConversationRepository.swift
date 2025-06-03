import Combine
import Foundation
import GRDB

protocol DraftConversationRepositoryProtocol: ConversationRepositoryProtocol {
    func subscribe(to writer: any DraftConversationWriterProtocol)
}

class DraftConversationRepository: DraftConversationRepositoryProtocol {
    private let dbReader: any DatabaseReader
    private var cancellables: Set<AnyCancellable> = []
    private var conversationWriterCancellable: AnyCancellable?

    private let messagesRepositoryPassThroughSubject: PassthroughSubject<any MessagesRepositoryProtocol, Never> =
        .init()
    var messagesRepositoryPublisher: AnyPublisher<any MessagesRepositoryProtocol, Never> {
        messagesRepositoryPassThroughSubject.eraseToAnyPublisher()
    }

    private let conversationIdSubject: CurrentValueSubject<String?, Never> = .init(nil)

    init(dbReader: any DatabaseReader, writer: any DraftConversationWriterProtocol) {
        self.dbReader = dbReader
        conversationPublisher
            .compactMap { $0 }
            .map { MessagesRepository(dbReader: self.dbReader, conversationId: $0.id) }
            .sink { [weak self] repository in
                guard let self else { return }
                messagesRepositoryPassThroughSubject.send(repository)
            }
            .store(in: &cancellables)
        subscribe(to: writer)
    }

    func subscribe(to writer: any DraftConversationWriterProtocol) {
        conversationWriterCancellable = writer.conversationIdPublisher
            .sink { [weak self] conversationId in
                guard let self else { return }
                conversationIdSubject.send(conversationId)
            }
    }

    lazy var conversationPublisher: AnyPublisher<Conversation?, Never> = {
        conversationIdSubject
            .compactMap { $0 }
            .removeDuplicates()
            .flatMap { [weak self] conversationId -> AnyPublisher<Conversation?, Never> in
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
            .eraseToAnyPublisher()
    }()

    func fetchConversation() throws -> Conversation? {
        try dbReader.read { [weak self] db in
            guard let self else { return nil }
            guard let conversationId = conversationIdSubject.value else {
                return nil
            }
            return try db.composeConversation(for: conversationId)
        }
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
