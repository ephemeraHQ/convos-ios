import Combine
import Foundation
import GRDB

public protocol DraftConversationRepositoryProtocol: ConversationRepositoryProtocol {
    var messagesRepository: any MessagesRepositoryProtocol { get }
}

class DraftConversationRepository: DraftConversationRepositoryProtocol {
    private let dbReader: any DatabaseReader
    let conversationId: String
    private let conversationIdPublisher: AnyPublisher<String, Never>
    let messagesRepository: any MessagesRepositoryProtocol
    let myProfileRepository: any MyProfileRepositoryProtocol

    init(dbReader: any DatabaseReader,
         conversationId: String,
         conversationIdPublisher: AnyPublisher<String, Never>,
         inboxStateManager: any InboxStateManagerProtocol) {
        self.dbReader = dbReader
        self.conversationId = conversationId
        self.conversationIdPublisher = conversationIdPublisher
        Logger.info("Initializing DraftConversationRepository with conversationId: \(conversationId)")
        messagesRepository = MessagesRepository(
            dbReader: dbReader,
            conversationId: conversationId,
            conversationIdPublisher: conversationIdPublisher
        )
        myProfileRepository = MyProfileRepository(
            inboxStateManager: inboxStateManager,
            databaseReader: dbReader,
            conversationId: conversationId,
            conversationIdPublisher: conversationIdPublisher
        )
    }

    lazy var conversationPublisher: AnyPublisher<Conversation?, Never> = {
        Logger.info("Creating conversationPublisher for conversationId: \(conversationId)")
        return conversationIdPublisher
            .removeDuplicates()
            .flatMap { [weak self] conversationId -> AnyPublisher<Conversation?, Never> in
                guard let self else {
                    Logger.warning("DraftConversationRepository deallocated during conversationPublisher mapping")
                    return Just(nil).eraseToAnyPublisher()
                }

                Logger.info("Conversation ID changed to: \(conversationId)")
                return ValueObservation
                    .tracking { [weak self] db in
                        guard let self else {
                            Logger.warning("DraftConversationRepository deallocated during conversation tracking")
                            return nil
                        }
                        do {
                            Logger.debug("Tracking conversation \(conversationId)")

                            let conversation = try db.composeConversation(for: conversationId)
                            if conversation != nil {
                                Logger.info(
                                    "Composed conversation: \(conversationId) with kind: \(conversation?.kind ?? .dm)"
                                )
                            } else {
                                Logger.debug("No conversation found for ID: \(conversationId)")
                            }
                            return conversation
                        } catch {
                            Logger.error("Error composing conversation for ID \(conversationId): \(error)")
                            return nil
                        }
                    }
                    .publisher(in: dbReader)
                    .replaceError(with: nil)
                    .eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
    }()

    func fetchConversation() throws -> Conversation? {
        Logger.info("Fetching conversation for ID: \(conversationId)")
        do {
            let conversation: Conversation? = try dbReader.read { [weak self] db in
                guard let self else {
                    Logger.warning("DraftConversationRepository deallocated during fetchConversation")
                    return nil
                }
                return try db.composeConversation(for: self.conversationId)
            }
            if conversation != nil {
                Logger.info("Successfully fetched conversation: \(conversationId)")
            } else {
                Logger.debug("No conversation found for ID: \(conversationId)")
            }
            return conversation
        } catch {
            Logger.error("Error fetching conversation for ID \(conversationId): \(error)")
            throw error
        }
    }
}

fileprivate extension Database {
    func composeConversation(for conversationId: String) throws -> Conversation? {
        do {
            guard let dbConversation = try DBConversation
                .filter(DBConversation.Columns.clientConversationId == conversationId)
                .detailedConversationQuery()
                .fetchOne(self) else {
                return nil
            }

            let conversation = dbConversation.hydrateConversation()
            Logger.debug("Successfully hydrated conversation: \(conversationId)")
            return conversation
        } catch {
            Logger.error("Error composing conversation for ID \(conversationId): \(error)")
            throw error
        }
    }
}
