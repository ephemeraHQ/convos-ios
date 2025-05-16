import Foundation
import GRDB
import XMTPiOS

protocol SyncingManagerProtocol {
    func start(with client: Client)
}

class SyncingManager: SyncingManagerProtocol {
    private let conversationWriter: ConversationWriterProtocol

    init(databaseWriter: any DatabaseWriter) {
        self.conversationWriter = ConversationWriter(databaseWriter: databaseWriter)
    }

    func start(with client: Client) {
        Task {
            let conversations = try await client.conversations.list()
            for conversation in conversations {
                conversationWriter.store(conversation: conversation)
            }
        }
        Task {
            for try await conversation in await client.conversations.stream() {
            }
        }
    }
}
