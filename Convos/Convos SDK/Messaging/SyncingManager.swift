import Foundation
import GRDB
import XMTPiOS

protocol SyncingManagerProtocol {
    func start(with client: Client)
}

class SyncingManager: SyncingManagerProtocol {
    private let conversationWriter: ConversationWriterProtocol
    private let messageWriter: MessageWriterProtocol
    private let apiClient: ConvosAPIClient

    init(databaseWriter: any DatabaseWriter,
         apiClient: ConvosAPIClient) {
        self.apiClient = apiClient
        self.conversationWriter = ConversationWriter(databaseWriter: databaseWriter)
        self.messageWriter = MessageWriter(databaseWriter: databaseWriter)
    }

    func start(with client: Client) {
        Task {
            do {
                _ = try await client.conversations.syncAllConversations()
            } catch {
                Logger.error("Error syncing all conversations: \(error)")
            }
        }
        Task {
            do {
                let maxConcurrentTasks = 5
                let conversations = try await client.conversations.list()
                for chunk in conversations.chunked(into: maxConcurrentTasks) {
                    // we also want to:
                    // - fetch the last message for each conversation after saving
                    // - for all dms, fetch the profile of the other participant
                    syncMemberProfiles(for: chunk)
                    try await withThrowingTaskGroup(of: Void.self) { group in
                        for conversation in chunk {
                            group.addTask {
                                try await conversation.sync()
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
                for try await message in await client.conversations.streamAllMessages() {
                    try await messageWriter.store(message: message)
                }
            } catch {
                Logger.error("Error streaming all messages: \(error)")
            }
        }
        Task {
            do {
                for try await conversation in await client.conversations.stream() {
                    try await conversation.sync()
                    try await conversationWriter.store(conversation: conversation)
                }
            } catch {
                Logger.error("Error streaming conversations: \(error)")
            }
        }
    }

    // MARK: - Private

    private func syncMemberProfiles(for conversations: [XMTPiOS.Conversation]) {
        Task {
            let allMemberIds = await withTaskGroup(
                of: [XMTPiOS.Member].self,
                returning: [String].self) { group in
                    for conversation in conversations {
                        group.addTask {
                            (try? await conversation.members()) ?? []
                        }
                    }
                    var allMemberIds: Set<InboxId> = .init()
                    for await members in group {
                        allMemberIds.formUnion(members.map(\.inboxId))
                    }
                    return allMemberIds.map { $0 as String }
                }
            let maxMembersPerChunk = 100
            for chunk in allMemberIds.chunked(into: maxMembersPerChunk) {
                Task {
                    let profiles = try await apiClient.getProfiles(for: chunk)
                    // store profiles
                }
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
