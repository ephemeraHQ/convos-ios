import Foundation
import GRDB
import XMTPiOS

protocol MessageWriterProtocol {
    func store(message: XMTPiOS.DecodedMessage) async throws
}

class MessageWriter: MessageWriterProtocol {
    private let databaseWriter: any DatabaseWriter

    init(databaseWriter: any DatabaseWriter) {
        self.databaseWriter = databaseWriter
    }

    func store(message: DecodedMessage) async throws {
        let conversationId = message.conversationId
        let dbLastMessage = try message.dbRepresentation(
            conversationId: conversationId,
            sender: .empty
        )
        try await databaseWriter.write { db in
            // TODO: the message save will fail if the conversation doesn't exist
            if var conversation = try DBConversation
                .filter(Column("id") == conversationId)
                .fetchOne(db) {
                conversation.lastMessage = .init(text: (try? message.body) ?? "",
                                                 createdAt: message.sentAt)
                try conversation.update(db)
            }

            if let dbLastMessage = dbLastMessage as? any PersistableRecord {
                try dbLastMessage.save(db)
            } else {
                Logger.error("Error saving last message, could not cast to PersistableRecord")
            }
        }
    }
}
