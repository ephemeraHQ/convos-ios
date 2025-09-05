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
    private let memberProfileSyncInterval: TimeInterval = 120 // seconds

    init(databaseWriter: any DatabaseWriter) {
        let messageWriter = IncomingMessageWriter(databaseWriter: databaseWriter)
        self.conversationWriter = ConversationWriter(databaseWriter: databaseWriter,
                                                     messageWriter: messageWriter)
        self.messageWriter = messageWriter
        self.profileWriter = MemberProfileWriter(databaseWriter: databaseWriter)
    }

    func start(with client: AnyClientProvider, apiClient: any ConvosAPIClientProtocol) {
        // each client (currently) has one conversation
        listConversationsTask = Task { [weak self] in
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
                                    _ = try await conversationWriter.storeWithLatestMessages(
                                        conversation: conversation
                                    )
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
        // Start the streaming tasks
        startMessageStream(client: client, apiClient: apiClient)
        startConversationStream(client: client, apiClient: apiClient)
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

    private let maxStreamRetries: Int = 5

    private func startMessageStream(client: AnyClientProvider, apiClient: any ConvosAPIClientProtocol, retryCount: Int = 0) {
        guard retryCount < maxStreamRetries else {
            Logger.error("Messages stream max retries (\(maxStreamRetries)) reached for inbox: \(client.inboxId). Giving up.")
            return
        }

        Logger.info("Starting messages stream for inbox: \(client.inboxId) (retry: \(retryCount))")
        streamMessagesTask = Task { [weak self] in
            do {
                guard let self else { return }

                let delay = TimeInterval.calculateExponentialBackoff(for: retryCount)
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

                // if we're coming from the stream calling `onClose`, syncAll before re-starting
                if retryCount > 0 {
                    do {
                        _ = try await client.conversationsProvider.syncAllConversations(consentStates: consentStates)
                    } catch {
                        Logger.error("Error syncing all conversations: \(error)")
                    }
                }

                for try await message in client.conversationsProvider
                    .streamAllMessages(
                        type: .groups,
                        consentStates: consentStates,
                        onClose: { [weak self] in
                            guard let self, !Task.isCancelled else { return }
                            // Check if the stream task is still active before scheduling retry
                            guard let streamTask = self.streamMessagesTask, !streamTask.isCancelled else {
                                Logger.info("Messages stream task was cancelled, not restarting")
                                return
                            }
                            let nextRetry = retryCount + 1
                            Logger.warning("Messages stream closed for inboxId: \(client.inboxId). Restarting (retry \(nextRetry)/\(self.maxStreamRetries))...")
                            Task { [weak self] in
                                guard let self else { return }
                                // Double-check the stream task is still active
                                guard let streamTask = self.streamMessagesTask, !streamTask.isCancelled else {
                                    Logger.info("Messages stream task was cancelled, not restarting")
                                    return
                                }
                                self.startMessageStream(client: client, apiClient: apiClient, retryCount: nextRetry)
                            }
                        }
                    ) {
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
                // Restart on error as well
                guard !Task.isCancelled else { return }
                // Check if the stream task is still active before scheduling retry
                guard let streamTask = self?.streamMessagesTask, !streamTask.isCancelled else {
                    Logger.info("Messages stream task was cancelled, not restarting after error")
                    return
                }
                let nextRetry = retryCount + 1
                Task { [weak self] in
                    guard let self else { return }
                    // Double-check the stream task is still active
                    guard let streamTask = self.streamMessagesTask, !streamTask.isCancelled else {
                        Logger.info("Messages stream task was cancelled, not restarting after error")
                        return
                    }
                    self.startMessageStream(client: client, apiClient: apiClient, retryCount: nextRetry)
                }
            }
        }
    }

    private func startConversationStream(client: AnyClientProvider, apiClient: any ConvosAPIClientProtocol, retryCount: Int = 0) {
        guard retryCount < maxStreamRetries else {
            Logger.error("Conversations stream max retries (\(maxStreamRetries)) reached for inbox: \(client.inboxId). Giving up.")
            return
        }

        Logger.info("Starting conversations stream for inbox: \(client.inboxId) (retry: \(retryCount))")
        streamConversationsTask = Task { [weak self] in
            do {
                let delay = TimeInterval.calculateExponentialBackoff(for: retryCount)
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

                for try await conversation in client.conversationsProvider.stream(
                    type: .groups,
                    onClose: { [weak self] in
                        guard let self, !Task.isCancelled else { return }
                        // Check if the stream task is still active before scheduling retry
                        guard let streamTask = self.streamConversationsTask, !streamTask.isCancelled else {
                            Logger.info("Conversations stream task was cancelled, not restarting")
                            return
                        }
                        let nextRetry = retryCount + 1
                        Logger.warning("Conversations stream closed for inboxId: \(client.inboxId). Restarting (retry \(nextRetry)/\(self.maxStreamRetries))...")
                        Task { [weak self] in
                            guard let self else { return }
                            // Double-check the stream task is still active
                            guard let streamTask = self.streamConversationsTask, !streamTask.isCancelled else {
                                Logger.info("Conversations stream task was cancelled, not restarting")
                                return
                            }
                            self.startConversationStream(client: client, apiClient: apiClient, retryCount: nextRetry)
                        }
                    }
                ) {
                    guard let self else { return }
                    syncMemberProfiles(apiClient: apiClient, for: [conversation])
                    Logger.info("Syncing conversation with id: \(conversation.id)")
                    try await conversationWriter.store(conversation: conversation)
                }
            } catch {
                Logger.error("Error streaming conversations: \(error)")
                // Restart on error as well
                guard !Task.isCancelled else { return }
                // Check if the stream task is still active before scheduling retry
                guard let streamTask = self?.streamConversationsTask, !streamTask.isCancelled else {
                    Logger.info("Conversations stream task was cancelled, not restarting after error")
                    return
                }
                let nextRetry = retryCount + 1
                Task { [weak self] in
                    guard let self else { return }
                    // Double-check the stream task is still active
                    guard let streamTask = self.streamConversationsTask, !streamTask.isCancelled else {
                        Logger.info("Conversations stream task was cancelled, not restarting after error")
                        return
                    }
                    self.startConversationStream(client: client, apiClient: apiClient, retryCount: nextRetry)
                }
            }
        }
    }

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
