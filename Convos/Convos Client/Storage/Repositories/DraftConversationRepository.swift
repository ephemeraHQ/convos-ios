import Combine
import Foundation
import GRDB

protocol DraftConversationRepositoryProtocol: ConversationRepositoryProtocol {
    var selectedConversationId: String? { get set }
}

class DraftConversationRepository: DraftConversationRepositoryProtocol {
    private let draftConversationId: String
    private let dbReader: any DatabaseReader
    private var cancellables: Set<AnyCancellable> = []

    private let messagesRepositoryPassThroughSubject: PassthroughSubject<any MessagesRepositoryProtocol, Never> =
        .init()
    var messagesRepositoryPublisher: AnyPublisher<any MessagesRepositoryProtocol, Never> {
        messagesRepositoryPassThroughSubject.eraseToAnyPublisher()
    }

    private let conversationIdSubject: CurrentValueSubject<String, Never>
    private var conversationId: String {
        get { conversationIdSubject.value }
        set { conversationIdSubject.send(newValue) }
    }

    var selectedConversationId: String? {
        didSet {
            if let selectedConversationId {
                conversationId = selectedConversationId
            } else {
                conversationId = draftConversationId
            }
        }
    }

    init(dbReader: any DatabaseReader, draftConversationId: String) {
        self.draftConversationId = draftConversationId
        self.dbReader = dbReader
        self.conversationIdSubject = CurrentValueSubject(draftConversationId)
        conversationPublisher
            .compactMap { $0 }
            .removeDuplicates(by: { lhs, rhs in
                return lhs.id == rhs.id
            })
            .map { MessagesRepository(dbReader: self.dbReader, conversationId: $0.id) }
            .sink { [weak self] repository in
                guard let self else { return }
                messagesRepositoryPassThroughSubject.send(repository)
            }
            .store(in: &cancellables)
    }

    lazy var conversationPublisher: AnyPublisher<Conversation?, Never> = {
        conversationIdSubject
            .removeDuplicates()
            .flatMap { [weak self] conversationId -> AnyPublisher<Conversation?, Never> in
                guard let self else {
                    return Just(nil).eraseToAnyPublisher()
                }

                return ValueObservation
                    .tracking { [weak self] db in
                        guard let self else { return nil }

                        guard let currentUser = try db.currentUser() else {
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
            .eraseToAnyPublisher()
    }()
}
