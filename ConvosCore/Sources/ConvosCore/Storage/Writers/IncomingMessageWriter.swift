import Foundation
import GRDB
import XMTPiOS

public protocol IncomingMessageWriterProtocol {
    func store(message: XMTPiOS.DecodedMessage,
               for conversation: DBConversation) async throws
}

class IncomingMessageWriter: IncomingMessageWriterProtocol {
    private let databaseWriter: any DatabaseWriter

    init(databaseWriter: any DatabaseWriter) {
        self.databaseWriter = databaseWriter
    }

    func store(message: DecodedMessage,
               for conversation: DBConversation) async throws {
        try await databaseWriter.write { db in
            let sender = Member(inboxId: message.senderInboxId)
            try sender.save(db)
            let senderProfile = MemberProfile(
                inboxId: message.senderInboxId,
                name: nil,
                avatar: nil
            )
            try? senderProfile.insert(db)
            let message = try message.dbRepresentation()

            // @jarodl temporary, this should happen somewhere else more explicitly
            let wasRemovedFromConversation = message.update?.removedInboxIds.contains(conversation.inboxId) ?? false
            guard !wasRemovedFromConversation else {
                Logger.info("Removed from conversation, skipping message store and deleting conversation...")
                NotificationCenter.default.post(
                    name: .leftConversationNotification,
                    object: nil,
                    userInfo: ["inboxId": conversation.inboxId, "conversationId": conversation.id]
                )
                return
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
                Logger
                    .info(
                        "Updated incoming message with local message \(localMessage.clientMessageId)"
                    )
            } else {
                do {
                    try message.save(db)
                } catch {
                    Logger.error("Failed saving incoming message \(message.id): \(error)")
                }
            }

            if let localState = try ConversationLocalState
                .filter(Column("conversationId") == conversation.id)
                .fetchOne(db) {
                Logger.info("Marking conversation as unread: \(conversation.id)")
                if localState.isUnreadUpdatedAt < message.date {
                    try localState.with(isUnread: true).save(db)
                }
            } else {
                Logger.info("Creating local state for conversation: \(conversation.id)")
                try ConversationLocalState(
                    conversationId: conversation.id,
                    isPinned: false,
                    isUnread: true,
                    isUnreadUpdatedAt: Date(),
                    isMuted: false
                ).save(db)
            }
        }
    }
}
