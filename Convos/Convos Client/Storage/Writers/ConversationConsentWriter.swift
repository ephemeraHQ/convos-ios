import Combine
import Foundation
import GRDB

protocol ConversationConsentWriterProtocol {
    func join(conversation: Conversation) async throws
    func delete(conversation: Conversation) async throws
}

class ConversationConsentWriter: ConversationConsentWriterProtocol {
    enum ConversationConsentWriterError: Error {
        case missingXMTPClient
    }

    private let databaseWriter: any DatabaseWriter
    private var clientProvider: (any XMTPClientProvider)?
    private var cancellable: AnyCancellable?

    init(databaseWriter: any DatabaseWriter,
         clientPublisher: AnyPublisher<(any XMTPClientProvider)?, Never>) {
        self.databaseWriter = databaseWriter
        cancellable = clientPublisher.sink { [weak self] clientProvider in
            guard let self else { return }
            self.clientProvider = clientProvider
        }
    }

    func join(conversation: Conversation) async throws {
        guard let clientProvider else {
            throw ConversationConsentWriterError.missingXMTPClient
        }
        try await clientProvider.update(consent: .allowed, for: conversation)
        try await databaseWriter.write { db in
            if let localConversation = try DBConversation
                .filter(DBConversation.Columns.id == conversation.id)
                .fetchOne(db) {
                let updatedConversation = localConversation.with(
                    consent: .allowed
                )
                try updatedConversation.save(db)
                Logger.info("Updated conversation consent state to allowed")
            }
        }
    }

    func delete(conversation: Conversation) async throws {
        guard let clientProvider else {
            throw ConversationConsentWriterError.missingXMTPClient
        }
        try await clientProvider.update(consent: .denied, for: conversation)
        try await databaseWriter.write { db in
            if let localConversation = try DBConversation
                .filter(DBConversation.Columns.id == conversation.id)
                .fetchOne(db) {
                let updatedConversation = localConversation.with(
                    consent: .denied
                )
                try updatedConversation.save(db)
                Logger.info("Updated conversation consent state to denied")
            }
        }
    }
}
