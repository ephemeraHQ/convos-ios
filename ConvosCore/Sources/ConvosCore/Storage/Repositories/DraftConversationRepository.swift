import Combine
import Foundation
import GRDB

public protocol DraftConversationRepositoryProtocol: ConversationRepositoryProtocol {
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
        Logger.info("Initializing DraftConversationRepository with conversationId: \(writer.conversationId)")
        messagesRepository = MessagesRepository(
            dbReader: dbReader,
            conversationId: writer.conversationId,
            conversationIdPublisher: writer.conversationIdPublisher
        )
    }

    lazy var conversationPublisher: AnyPublisher<Conversation?, Never> = {
        Logger.info("Creating conversationPublisher for conversationId: \(writer.conversationId)")
        return writer.conversationIdPublisher
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
        Logger.info("Fetching conversation for ID: \(writer.conversationId)")
        do {
            let conversation: Conversation? = try dbReader.read { [weak self] db in
                guard let self else {
                    Logger.warning("DraftConversationRepository deallocated during fetchConversation")
                    return nil
                }
                return try db.composeConversation(for: writer.conversationId)
            }
            if conversation != nil {
                Logger.info("Successfully fetched conversation: \(writer.conversationId)")
            } else {
                Logger.debug("No conversation found for ID: \(writer.conversationId)")
            }
            return conversation
        } catch {
            Logger.error("Error fetching conversation for ID \(writer.conversationId): \(error)")
            throw error
        }
    }
}

fileprivate extension Database {
    func composeConversation(for conversationId: String) throws -> Conversation? {
        do {
            guard let dbConversation = try DBConversation
                .filter(Column("clientConversationId") == conversationId)
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
