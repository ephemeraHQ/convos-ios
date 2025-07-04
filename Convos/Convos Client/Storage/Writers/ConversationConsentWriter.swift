import Foundation
import GRDB

protocol ConversationConsentWriterProtocol {
    func join(conversation: Conversation) async throws
    func delete(conversation: Conversation) async throws
    func deleteAll() async throws
}

class ConversationConsentWriter: ConversationConsentWriterProtocol {
    enum ConversationConsentWriterError: Error {
        case deleteAllFailedWithErrors([Error])
    }

    actor ErrorCollector {
        var errors: [Error] = []
        func append(_ error: Error) {
            errors.append(error)
        }
    }

    private let databaseWriter: any DatabaseWriter
    private let clientPublisher: AnyClientProviderPublisher
    private let clientValue: PublisherValue<AnyClientProvider>

    init(client: AnyClientProvider?,
         clientPublisher: AnyClientProviderPublisher,
         databaseWriter: any DatabaseWriter) {
        self.clientValue = .init(initial: client, upstream: clientPublisher)
        self.clientPublisher = clientPublisher
        self.databaseWriter = databaseWriter
    }

    func join(conversation: Conversation) async throws {
        guard let client = clientValue.value else {
            throw InboxStateError.inboxNotReady
        }

        try await client.update(consent: .allowed, for: conversation.id)
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
        guard let client = clientValue.value else {
            throw InboxStateError.inboxNotReady
        }

        try await client.update(consent: .denied, for: conversation.id)
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
        guard let client = clientValue.value else {
            throw InboxStateError.inboxNotReady
        }

        let conversationsToDeny: [DBConversation] = try await databaseWriter.read { db in
            try DBConversation
                .filter(DBConversation.Columns.inboxId == client.inboxId)
                .filter(DBConversation.Columns.consent == Consent.unknown)
                .fetchAll(db)
        }

        let errorCollector = ErrorCollector()

        await withTaskGroup(of: Void.self) { [client] group in
            for dbConversation in conversationsToDeny {
                group.addTask {
                    do {
                        try await client.update(consent: .denied, for: dbConversation.id)
                        try await self.databaseWriter.write { db in
                            let updatedConversation = dbConversation.with(consent: .denied)
                            try updatedConversation.save(db)
                            Logger.info("Updated conversation \(dbConversation.id) consent state to denied")
                        }
                    } catch {
                        await errorCollector.append(error)
                    }
                }
            }
            await group.waitForAll()
        }

        let errors = await errorCollector.errors
        if !errors.isEmpty {
            throw ConversationConsentWriterError.deleteAllFailedWithErrors(errors)
        }
    }
}
