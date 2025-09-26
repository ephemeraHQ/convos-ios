import Foundation
import GRDB
import XMTPiOS

public struct IncomingMessageWriterResult {
    public let contentType: MessageContentType
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
        try await databaseWriter.write { db in
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

            let result: IncomingMessageWriterResult = .init(contentType: message.contentType)

            // @jarodl temporary, this should happen somewhere else more explicitly
            let wasRemovedFromConversation = message.update?.removedInboxIds.contains(conversation.inboxId) ?? false
            guard !wasRemovedFromConversation else {
                Logger.info("Removed from conversation, skipping message store and deleting conversation...")
                NotificationCenter.default.post(
                    name: .leftConversationNotification,
                    object: nil,
                    userInfo: ["inboxId": conversation.inboxId, "conversationId": conversation.id]
                )
                return result
            }

            Logger.info("Storing incoming message \(message.id) localId \(message.clientMessageId)")
            // see if this message has a local version
            if let localMessage = try DBMessage
                .filter(Column("id") == message.id)
                .filter(Column("clientMessageId") != message.id)
                .fetchOne(db) {
                // keep using the same local id
                Logger.info("Found local message \(localMessage.clientMessageId) for incoming message \(message.id)")
                let updatedMessage = message.with(
                    clientMessageId: localMessage.clientMessageId
                )
                try updatedMessage.save(db)
                Logger.info(
                    "Updated incoming message with local message \(localMessage.clientMessageId)"
                )
            } else {
                do {
                    try message.save(db)
                    Logger.info("Saved incoming message: \(message.id)")
                } catch {
                    Logger.error("Failed saving incoming message \(message.id): \(error)")
                    throw error
                }
            }

            return result
        }
    }
}
