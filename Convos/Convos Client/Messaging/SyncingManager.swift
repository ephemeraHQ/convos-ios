import Foundation
import GRDB
import XMTPiOS

protocol SyncingManagerProtocol {
    func start(with client: Client)
    func stop()
}

final class SyncingManager: SyncingManagerProtocol {
    private let conversationWriter: any ConversationWriterProtocol
    private let messageWriter: any IncomingMessageWriterProtocol
    private let apiClient: any ConvosAPIClientProtocol
    private let profileWriter: any MemberProfileWriterProtocol

    private var listConversationsTask: Task<Void, Never>?
    private var streamMessagesTask: Task<Void, Never>?
    private var streamConversationsTask: Task<Void, Never>?
    private var syncMemberProfilesTasks: [Task<Void, Error>] = []
    private let consentStates: [ConsentState] = [.allowed, .unknown]

    init(databaseWriter: any DatabaseWriter,
         apiClient: any ConvosAPIClientProtocol) {
        self.apiClient = apiClient
        let messageWriter = IncomingMessageWriter(databaseWriter: databaseWriter)
        self.conversationWriter = ConversationWriter(databaseWriter: databaseWriter,
                                                     messageWriter: messageWriter)
        self.messageWriter = messageWriter
        self.profileWriter = MemberProfileWriter(databaseWriter: databaseWriter)
    }

    func start(with client: Client) {
        listConversationsTask = Task {
            do {
                do {
                    _ = try await client.conversations.syncAllConversations(consentStates: consentStates)
                } catch {
                    Logger.error("Error syncing all conversations: \(error)")
                }
                let maxConcurrentTasks = 5
                let conversations = try await client.conversations.list(consentStates: consentStates)
                syncMemberProfiles(for: conversations)
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
        streamMessagesTask = Task {
            do {
                for try await message in await client.conversations.streamAllMessages(consentStates: consentStates) {
                    guard let conversation = try await client.conversations.findConversation(
                        conversationId: message.conversationId) else {
                        Logger.error("Failed finding conversation for message in `streamAllMessages()`")
                        continue
                    }
                    let dbConversation = try await conversationWriter.store(
                        conversation: conversation
                    )
                    try await messageWriter.store(message: message,
                                                  for: dbConversation)
                }
            } catch {
                Logger.error("Error streaming all messages: \(error)")
            }
        }
        streamConversationsTask = Task {
            do {
                for try await conversation in await client.conversations.stream() {
                    syncMemberProfiles(for: [conversation])
                    try await conversationWriter.store(conversation: conversation)
                }
            } catch {
                Logger.error("Error streaming conversations: \(error)")
            }
        }
    }

    func stop() {
        listConversationsTask?.cancel()
        listConversationsTask = nil
        streamMessagesTask?.cancel()
        streamMessagesTask = nil
        streamConversationsTask?.cancel()
        streamConversationsTask = nil
        syncMemberProfilesTasks.forEach { $0.cancel() }
        syncMemberProfilesTasks.removeAll()
    }

    // MARK: - Private

    private func syncMemberProfiles(for conversations: [XMTPiOS.Conversation]) {
        let syncProfilesTask = Task {
            do {
                let allMemberIds = try await withThrowingTaskGroup(
                    of: [XMTPiOS.Member].self,
                    returning: [String].self
                ) { group in
                    for conversation in conversations {
                        group.addTask {
                            try await conversation.members()
                        }
                    }
                    var allMemberIds: Set<InboxId> = .init()
                    for try await members in group {
                        allMemberIds.formUnion(members.map(\.inboxId))
                    }
                    return allMemberIds.map { $0 as String }
                }
                let maxMembersPerChunk = 100
                for chunk in allMemberIds.chunked(into: maxMembersPerChunk) {
                    let chunkTask = Task {
                        do {
                            let batchProfiles = try await apiClient.getProfiles(for: chunk)
                            let profiles = Array(batchProfiles.profiles.values)
                            try await profileWriter.store(profiles: profiles)
                        } catch {
                            Logger.error("Error syncing member profiles: \(error)")
                            throw error
                        }
                    }
                    syncMemberProfilesTasks.append(chunkTask)
                }
            } catch {
                Logger.error("Error syncing member profiles: \(error)")
                throw error
            }
        }
        syncMemberProfilesTasks.append(syncProfilesTask)
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
