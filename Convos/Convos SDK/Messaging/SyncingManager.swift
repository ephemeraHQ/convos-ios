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
            do {
                let maxConcurrentTasks = 5
                let conversations = try await client.conversations.list()
                for chunk in conversations.chunked(into: maxConcurrentTasks) {
                    try await withThrowingTaskGroup(of: Void.self) { group in
                        for conversation in chunk {
                            
                            group.addTask {
                                try await self.conversationWriter.store(conversation: conversation)
                            }
                        }
                        try await group.waitForAll()
                    }
                }
            } catch {
                Logger.error("Error syncing conversations: \(error)")
            }
        }
        Task {
            do {
                for try await conversation in await client.conversations.stream() {
                    try await conversationWriter.store(conversation: conversation)
                }
            } catch {
                Logger.error("Error streaming conversations: \(error)")
            }
        }
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
