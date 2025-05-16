import Foundation
import GRDB
import XMTPiOS

protocol ConversationWriterProtocol {
    func store(conversation: XMTPiOS.Conversation) async throws
}

class ConversationWriter: ConversationWriterProtocol {
    private let databaseWriter: any DatabaseWriter

    init(databaseWriter: any DatabaseWriter) {
        self.databaseWriter = databaseWriter
    }

    func store(conversation: XMTPiOS.Conversation) async throws {
        let dbConversation = Conversation(id: conversation.id,
                                          isPinned: false,
                                          isUnread: false,
                                          isMuted: false)
        try await databaseWriter.write { db in
            try dbConversation.save(db)
        }
    }
}
