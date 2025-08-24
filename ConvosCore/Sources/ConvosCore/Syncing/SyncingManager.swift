import Foundation
import GRDB
import XMTPiOS

protocol SyncingManagerProtocol {
    func start(with client: AnyClientProvider,
               apiClient: any ConvosAPIClientProtocol)
    func stop()
}

final class SyncingManager: SyncingManagerProtocol {
    private let conversationWriter: any ConversationWriterProtocol
    private let messageWriter: any IncomingMessageWriterProtocol
    private let profileWriter: any MemberProfileWriterProtocol

    private var listConversationsTask: Task<Void, Never>?
    private var streamMessagesTask: Task<Void, Never>?
    private var streamConversationsTask: Task<Void, Never>?
    private var syncMemberProfilesTasks: [Task<Void, Error>] = []
    private let consentStates: [ConsentState] = [.allowed, .unknown]

    // Track last sync times for member profiles per conversation
    private var lastMemberProfileSync: [String: Date] = [:]
    private let memberProfileSyncInterval: TimeInterval = 10 // seconds

    init(databaseWriter: any DatabaseWriter) {
        let messageWriter = IncomingMessageWriter(databaseWriter: databaseWriter)
        self.conversationWriter = ConversationWriter(databaseWriter: databaseWriter,
                                                     messageWriter: messageWriter)
        self.messageWriter = messageWriter
        self.profileWriter = MemberProfileWriter(databaseWriter: databaseWriter)
    }

    func start(with client: AnyClientProvider, apiClient: any ConvosAPIClientProtocol) {
        listConversationsTask = Task { [weak self, consentStates] in
            do {
                guard let self else { return }
                do {
                    _ = try await client.conversationsProvider.syncAllConversations(consentStates: consentStates)
                } catch {
                    Logger.error("Error syncing all conversations: \(error)")
                }
                let maxConcurrentTasks = 5
                let conversations = try await client.conversationsProvider.list(
                    createdAfter: nil,
                    createdBefore: nil,
                    limit: nil,
                    consentStates: consentStates
                )
                syncMemberProfiles(apiClient: apiClient, for: conversations)
                for chunk in conversations.chunked(into: maxConcurrentTasks) {
                    try await withThrowingTaskGroup(of: Void.self) { group in
                        for conversation in chunk {
                            group.addTask { [weak self] in
                                guard let self else { return }
                                if case .group = conversation {
                                    try await conversationWriter.store(conversation: conversation)
                                } else {
                                    Logger.info("Listed DM, ignoring...")
                                }
                            }
                        }
                        try await group.waitForAll()
                    }
                }
            } catch {
                Logger.error("Error syncing conversations: \(error)")
            }
        }
        streamMessagesTask = Task { [weak self, consentStates] in
            do {
                for try await message in await client.conversationsProvider
                    .streamAllMessages(
                        type: .groups,
                        consentStates: consentStates,
                        onClose: {
                            Logger.warning("Closing messages stream for inboxId: \(client.inboxId)...")
                        }
                    ) {
                    guard let self else { return }
                    guard let conversation = try await client.conversationsProvider.findConversation(
                        conversationId: message.conversationId
                    ) else {
                        Logger.error("Failed finding conversation for message in `streamAllMessages()`")
                        continue
                    }
                    syncMemberProfiles(apiClient: apiClient, for: conversation)
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
        streamConversationsTask = Task { [weak self] in
            do {
                for try await conversation in await client.conversationsProvider.stream(
                    type: .groups,
                    onClose: {
                        Logger.warning("Closing conversations stream for inboxId: \(client.inboxId)...")
                    }
                ) {
                    guard let self else { return }
                    syncMemberProfiles(apiClient: apiClient, for: [conversation])
                    Logger.info("Syncing conversation with id: \(conversation.id)")
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

    private func syncMemberProfiles(
        apiClient: any ConvosAPIClientProtocol,
        for conversation: XMTPiOS.Conversation
    ) {
        let conversationId = conversation.id
        let now = Date()
        if let lastSync = lastMemberProfileSync[conversationId],
           now.timeIntervalSince(lastSync) < memberProfileSyncInterval {
            // Skip sync if less than 2 minutes have passed
        } else {
            // Update last sync time and sync
            lastMemberProfileSync[conversationId] = now
            syncMemberProfiles(apiClient: apiClient, for: [conversation])
        }
    }

    private func syncMemberProfiles(
        apiClient: any ConvosAPIClientProtocol,
        for conversations: [XMTPiOS.Conversation]
    ) {
        let syncProfilesTask = Task { [weak self] in
            guard let self else { return }
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
                    let chunkTask = Task { [weak self] in
                        guard let self else { return }
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
