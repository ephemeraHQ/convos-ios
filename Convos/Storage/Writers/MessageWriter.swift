import Foundation
import GRDB
import XMTPiOS

protocol MessageWriterProtocol {
    func store(message: XMTPiOS.DecodedMessage,
               for conversation: DBConversation) async throws
}

class MessageWriter: MessageWriterProtocol {
    private let databaseWriter: any DatabaseWriter

    init(databaseWriter: any DatabaseWriter) {
        self.databaseWriter = databaseWriter
    }

    func store(message: DecodedMessage,
               for conversation: DBConversation) async throws {
        try await databaseWriter.write { db in
            let conversationId = message.conversationId
//            let conversation = try DBConversation
//                .filter(Column("id") == message.conversationId)
//                .fetchOne(db)
            let sender = Member(inboxId: message.senderInboxId)
            let senderProfile = try MemberProfile
                .filter(Column("inboxId") == message.senderInboxId)
                .fetchOne(db)
            let message = try message.dbRepresentation(
                conversationId: conversationId
            )

            try sender.save(db)
            try message.save(db)
        }
    }
}
