import Combine
import Foundation
import GRDB

protocol ConversationConsentWriterProtocol {
    func join(conversation: Conversation) async throws
    func delete(conversation: Conversation) async throws
    func deleteAll() async throws
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
        try await clientProvider.update(consent: .allowed, for: conversation.id)
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
        try await clientProvider.update(consent: .denied, for: conversation.id)
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

    func deleteAll() async throws {
        guard let clientProvider else {
            throw ConversationConsentWriterError.missingXMTPClient
        }
        let conversationsToDeny: [DBConversation] = try await databaseWriter.read { db in
            try DBConversation
                .filter(DBConversation.Columns.consent == Consent.unknown)
                .fetchAll(db)
        }
        for dbConversation in conversationsToDeny {
            try await clientProvider.update(consent: .denied, for: dbConversation.id)
            try await databaseWriter.write { db in
                let updatedConversation = dbConversation.with(consent: .denied)
                try updatedConversation.save(db)
                Logger.info("Updated conversation \(dbConversation.id) consent state to denied")
            }
        }
    }
}
