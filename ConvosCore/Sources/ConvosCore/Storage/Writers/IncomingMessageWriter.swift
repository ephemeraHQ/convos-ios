import Foundation
import GRDB
import XMTPiOS

public struct IncomingMessageWriterResult {
    public let contentType: MessageContentType
    public let wasRemovedFromConversation: Bool
    public let messageAlreadyExists: Bool
}

public protocol IncomingMessageWriterProtocol {
    func store(message: XMTPiOS.DecodedMessage,
               for conversation: DBConversation) async throws -> IncomingMessageWriterResult
}

class IncomingMessageWriter: IncomingMessageWriterProtocol {
    private let databaseWriter: any DatabaseWriter

    init(databaseWriter: any DatabaseWriter) {
        self.databaseWriter = databaseWriter
    }

    func store(message: DecodedMessage,
               for conversation: DBConversation) async throws -> IncomingMessageWriterResult {
        let result = try await databaseWriter.write { db in
            let sender = Member(inboxId: message.senderInboxId)
            try sender.save(db)
            let senderProfile = MemberProfile(
                conversationId: conversation.id,
                inboxId: message.senderInboxId,
                name: nil,
                avatar: nil
            )
            try? senderProfile.insert(db)
            let message = try message.dbRepresentation()

            let messageExistsInDB = try DBMessage.exists(db, key: message.id)
            // @jarodl temporary, this should happen somewhere else more explicitly
            let wasRemovedFromConversation = message.update?.removedInboxIds.contains(conversation.inboxId) ?? false

            Log.info("Storing incoming message \(message.id) localId \(message.clientMessageId)")
            // see if this message has a local version
            if let localMessage = try DBMessage
                .filter(DBMessage.Columns.id == message.id)
                .filter(DBMessage.Columns.clientMessageId != message.id)
                .fetchOne(db) {
                // keep using the same local id
                Log.info("Found local message \(localMessage.clientMessageId) for incoming message \(message.id)")
                let updatedMessage = message.with(
                    clientMessageId: localMessage.clientMessageId
                )
                try updatedMessage.save(db)
                Log.info(
                    "Updated incoming message with local message \(localMessage.clientMessageId)"
                )
            } else {
                do {
                    try message.save(db)
                    Log.info("Saved incoming message: \(message.id)")
                } catch {
                    Log.error("Failed saving incoming message \(message.id): \(error)")
                    throw error
                }
            }

            return IncomingMessageWriterResult(
                contentType: message.contentType,
                wasRemovedFromConversation: wasRemovedFromConversation,
                messageAlreadyExists: messageExistsInDB
            )
        }

        // Post notification after transaction commits
        if result.wasRemovedFromConversation && !result.messageAlreadyExists {
            conversation.postLeftConversationNotification()
        }

        return result
    }
}
