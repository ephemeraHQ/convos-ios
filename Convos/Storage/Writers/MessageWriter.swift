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
        try await databaseWriter.write { db in
            let conversationId = message.conversationId
            let conversation = try DBConversation
                .filter(Column("id") == message.conversationId)
                .fetchCount(db)
            let sender = try MemberProfile
                .filter(Column("inboxId") == message.senderInboxId)
                .fetchOne(db)
            let dbLastMessage = try message.dbRepresentation(
                conversationId: conversationId
            )

            try dbLastMessage.save(db)
        }
    }
}
