import Foundation
import GRDB
import UIKit
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
    private let localStateWriter: any ConversationLocalStateWriterProtocol

    private var listConversationsTask: Task<Void, Never>?
    private var streamMessagesTask: Task<Void, Never>?
    private var streamConversationsTask: Task<Void, Never>?
    private var syncMemberProfilesTasks: [Task<Void, Error>] = []
    private let consentStates: [ConsentState] = [.allowed]

    // Track last sync times for member profiles per conversation
    private var lastMemberProfileSync: [String: Date] = [:]
    private let memberProfileSyncInterval: TimeInterval = 120 // seconds

    // Track when the last message was processed
    private var lastProcessedMessageAt: Date?

    // Track when the app was last active (for connectivity changes)
    private var lastActiveAt: Date? {
        get {
            let timestamp = UserDefaults.standard.double(forKey: lastActiveTimestampKey)
            guard timestamp > 0 else {
                return nil
            }
            return Date(timeIntervalSince1970: timestamp)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: lastActiveTimestampKey)
        }
    }
    private let lastActiveTimestampKey: String = "org.convos.SyncingManager.lastActiveTimestamp"

    // Track the currently active conversation
    private var activeConversationId: String?
    private var activeConversationObserver: Any?
    private var appLifecycleObservers: [Any] = []

    init(databaseWriter: any DatabaseWriter) {
        let messageWriter = IncomingMessageWriter(databaseWriter: databaseWriter)
        self.conversationWriter = ConversationWriter(databaseWriter: databaseWriter,
                                                     messageWriter: messageWriter)
        self.messageWriter = messageWriter
        self.profileWriter = MemberProfileWriter(databaseWriter: databaseWriter)
        self.localStateWriter = ConversationLocalStateWriter(databaseWriter: databaseWriter)

        setupObservers()
    }

    deinit {
        if let activeConversationObserver {
            NotificationCenter.default.removeObserver(activeConversationObserver)
        }
        appLifecycleObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    private func setupObservers() {
        activeConversationObserver = NotificationCenter.default
            .addObserver(forName: .activeConversationChanged, object: nil, queue: .main) { [weak self] notification in
                self?.activeConversationId = notification.userInfo?["conversationId"] as? String
            }

        // Set up app lifecycle observers
        let willResignActiveObserver = NotificationCenter.default
            .addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                self?.handleAppWillResignActive()
            }

        let willTerminateObserver = NotificationCenter.default
            .addObserver(forName: UIApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
                self?.handleAppWillTerminate()
            }

        let didBecomeActiveObserver = NotificationCenter.default
            .addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                self?.handleAppDidBecomeActive()
            }

        appLifecycleObservers = [willResignActiveObserver, willTerminateObserver, didBecomeActiveObserver]
    }

    func start(with client: AnyClientProvider, apiClient: any ConvosAPIClientProtocol) {
        listConversationsTask = Task { [weak self] in
            await self?.syncAllConversations(client: client, apiClient: apiClient)
        }
        // Start the streaming tasks
        startMessageStream(client: client, apiClient: apiClient)
        startConversationStream(client: client, apiClient: apiClient)
    }

    private func syncAllConversations(client: AnyClientProvider, apiClient: any ConvosAPIClientProtocol) async {
        do {
            // Sync all conversations first
            do {
                _ = try await client.conversationsProvider.syncAllConversations(consentStates: consentStates)
            } catch {
                Logger.error("Error syncing all conversations: \(error)")
            }

            // List all conversations
            let conversations = try await client.conversationsProvider.list(
                createdAfter: nil,
                createdBefore: nil,
                limit: nil,
                consentStates: consentStates
            )

            // Sync member profiles
            syncMemberProfiles(apiClient: apiClient, for: conversations)

            // Catch up on messages if we have a last active timestamp
            if let lastActiveAt = self.lastActiveAt {
                await catchUpMessages(
                    for: conversations,
                    since: lastActiveAt,
                    client: client
                )
                self.lastActiveAt = nil
            }

            // Store conversations with latest messages
            await storeConversationsWithLatestMessages(conversations)
        } catch {
            Logger.error("Error syncing conversations: \(error)")
        }
    }

    private func storeConversationsWithLatestMessages(_ conversations: [XMTPiOS.Conversation]) async {
        let maxConcurrentTasks = 5
        for chunk in conversations.chunked(into: maxConcurrentTasks) {
            do {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    for conversation in chunk {
                        group.addTask { [weak self] in
                            guard let self else { return }
                            if case .group = conversation {
                                try await conversationWriter.storeWithLatestMessages(
                                    conversation: conversation
                                )
                            } else {
                                Logger.info("Listed DM, ignoring...")
                            }
                        }
                    }
                    try await group.waitForAll()
                }
            } catch {
                Logger.error("Error storing conversations with latest messages: \(error)")
            }
        }
    }

    func stop() {
        // Save the current timestamp when stopping
        lastActiveAt = Date()

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
                try await self.processMessageStream(client: client, apiClient: apiClient, retryCount: retryCount)
            } catch {
                self?.handleMessageStreamError(
                    error: error,
                    client: client,
                    apiClient: apiClient,
                    retryCount: retryCount
                )
            }
        }
    }

    private func processMessageStream(client: AnyClientProvider, apiClient: any ConvosAPIClientProtocol, retryCount: Int) async throws {
        let delay = TimeInterval.calculateExponentialBackoff(for: retryCount)
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

        // if we're coming from the stream calling `onClose`, syncAll before re-starting
        if retryCount > 0 {
            await syncAllConversationsBeforeRestart(client: client)
        }

        // Catch up on messages since last processed
        if let lastProcessedMessageAt {
            let conversations = try await client.conversationsProvider.list(
                createdAfter: nil,
                createdBefore: nil,
                limit: nil,
                consentStates: consentStates
            )
            await catchUpMessages(
                for: conversations,
                since: lastProcessedMessageAt,
                client: client
            )
        }

        for try await message in client.conversationsProvider
            .streamAllMessages(
                type: .groups,
                consentStates: consentStates,
                onClose: { [weak self] in
                    self?.scheduleMessageStreamRetry(client: client, apiClient: apiClient, retryCount: retryCount)
                }
            ) {
            await processStreamedMessage(
                message: message,
                client: client,
                apiClient: apiClient
            )
        }
    }

    private func syncAllConversationsBeforeRestart(client: AnyClientProvider) async {
        do {
            _ = try await client.conversationsProvider.syncAllConversations(consentStates: consentStates)
        } catch {
            Logger.error("Error syncing all conversations: \(error)")
        }
    }

    private func processStreamedMessage(message: DecodedMessage, client: AnyClientProvider, apiClient: any ConvosAPIClientProtocol) async {
        do {
            guard let conversation = try await client.conversationsProvider.findConversation(
                conversationId: message.conversationId
            ) else {
                Logger.error("Failed finding conversation for message in `streamAllMessages()`")
                return
            }
            syncMemberProfiles(apiClient: apiClient, for: conversation)
            let dbConversation = try await conversationWriter.store(conversation: conversation)
            try await messageWriter.store(message: message, for: dbConversation)

            // Update the last processed message timestamp
            lastProcessedMessageAt = max(self.lastProcessedMessageAt ?? message.sentAt, message.sentAt)

            // Mark conversation as unread if needed
            await markConversationUnreadIfNeeded(
                conversationId: conversation.id,
                messageInboxId: message.senderInboxId,
                clientInboxId: client.inboxId
            )
        } catch {
            Logger.error("Error processing streamed message: \(error)")
        }
    }

    private func scheduleMessageStreamRetry(client: AnyClientProvider, apiClient: any ConvosAPIClientProtocol, retryCount: Int) {
        scheduleStreamRetry(
            streamName: "Messages",
            client: client,
            apiClient: apiClient,
            retryCount: retryCount,
            isTaskActive: isMessageStreamTaskActive,
            startStream: startMessageStream
        )
    }

    private func handleMessageStreamError(error: Error, client: AnyClientProvider, apiClient: any ConvosAPIClientProtocol, retryCount: Int) {
        Logger.error("Error streaming all messages: \(error)")
        scheduleStreamRetry(
            streamName: "Messages",
            client: client,
            apiClient: apiClient,
            retryCount: retryCount,
            isTaskActive: isMessageStreamTaskActive,
            startStream: startMessageStream
        )
    }

    private func scheduleStreamRetry(
        streamName: String,
        client: AnyClientProvider,
        apiClient: any ConvosAPIClientProtocol,
        retryCount: Int,
        isTaskActive: @escaping () -> Bool,
        startStream: @escaping (AnyClientProvider, any ConvosAPIClientProtocol, Int) -> Void
    ) {
        guard !Task.isCancelled else { return }
        guard isTaskActive() else {
            Logger.info("\(streamName) stream task was cancelled, not restarting")
            return
        }

        let nextRetry = retryCount + 1
        Logger.warning("\(streamName) stream closed for inboxId: \(client.inboxId). Restarting (retry \(nextRetry)/\(maxStreamRetries))...")

        Task {
            guard isTaskActive() else {
                Logger.info("\(streamName) stream task was cancelled, not restarting")
                return
            }
            startStream(client, apiClient, nextRetry)
        }
    }

    private func isMessageStreamTaskActive() -> Bool {
        guard let streamTask = streamMessagesTask, !streamTask.isCancelled else {
            return false
        }
        return true
    }

    private func startConversationStream(client: AnyClientProvider, apiClient: any ConvosAPIClientProtocol, retryCount: Int = 0) {
        guard retryCount < maxStreamRetries else {
            Logger.error("Conversations stream max retries (\(maxStreamRetries)) reached for inbox: \(client.inboxId). Giving up.")
            return
        }

        Logger.info("Starting conversations stream for inbox: \(client.inboxId) (retry: \(retryCount))")
        streamConversationsTask = Task { [weak self] in
            guard let self else { return }
            do {
                let delay = TimeInterval.calculateExponentialBackoff(for: retryCount)
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

                for try await conversation in client.conversationsProvider.stream(
                    type: .groups,
                    onClose: { [weak self] in
                        self?.scheduleConversationStreamRetry(client: client, apiClient: apiClient, retryCount: retryCount)
                    }
                ) {
                    syncMemberProfiles(apiClient: apiClient, for: [conversation])
                    Logger.info("Syncing conversation with id: \(conversation.id)")
                    try await conversationWriter.storeWithLatestMessages(conversation: conversation)
                }
            } catch {
                self.handleConversationStreamError(error: error, client: client, apiClient: apiClient, retryCount: retryCount)
            }
        }
    }

    private func scheduleConversationStreamRetry(client: AnyClientProvider, apiClient: any ConvosAPIClientProtocol, retryCount: Int) {
        scheduleStreamRetry(
            streamName: "Conversations",
            client: client,
            apiClient: apiClient,
            retryCount: retryCount,
            isTaskActive: isConversationStreamTaskActive,
            startStream: startConversationStream
        )
    }

    private func handleConversationStreamError(error: Error, client: AnyClientProvider, apiClient: any ConvosAPIClientProtocol, retryCount: Int) {
        Logger.error("Error streaming conversations: \(error)")
        scheduleStreamRetry(
            streamName: "Conversations",
            client: client,
            apiClient: apiClient,
            retryCount: retryCount,
            isTaskActive: isConversationStreamTaskActive,
            startStream: startConversationStream
        )
    }

    private func isConversationStreamTaskActive() -> Bool {
        guard let streamTask = streamConversationsTask, !streamTask.isCancelled else {
            return false
        }
        return true
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

    // MARK: - Helper Methods

    private func catchUpMessages(
        for conversations: [XMTPiOS.Conversation],
        since timestamp: Date,
        client: AnyClientProvider
    ) async {
        let timestampNs = timestamp.nanosecondsSince1970
        Logger.info("Fetching messages since \(timestamp)")

        for conversation in conversations {
            guard case .group = conversation else {
                Logger.info("Skipping DM for catch-up messages...")
                continue
            }

            do {
                let messages = try await conversation.messages(
                    afterNs: timestampNs,
                    direction: .ascending
                )

                if !messages.isEmpty {
                    Logger.info("Found \(messages.count) messages since timestamp for conversation \(conversation.id)")
                    await storeMessages(
                        messages,
                        for: conversation,
                        client: client
                    )
                }
            } catch {
                Logger.error("Error fetching messages since timestamp for conversation \(conversation.id): \(error)")
            }
        }
    }

    private func storeMessages(
        _ messages: [DecodedMessage],
        for conversation: XMTPiOS.Conversation,
        client: AnyClientProvider
    ) async {
        do {
            let dbConversation = try await conversationWriter.store(conversation: conversation)
            for message in messages {
                try await messageWriter.store(message: message, for: dbConversation)

                // Update last processed message timestamp if applicable
                if lastProcessedMessageAt != nil {
                    lastProcessedMessageAt = max(lastProcessedMessageAt ?? message.sentAt, message.sentAt)
                }

                // Mark conversation as unread if needed
                await markConversationUnreadIfNeeded(
                    conversationId: conversation.id,
                    messageInboxId: message.senderInboxId,
                    clientInboxId: client.inboxId
                )
            }
        } catch {
            Logger.error("Error storing messages: \(error)")
        }
    }

    private func markConversationUnreadIfNeeded(
        conversationId: String,
        messageInboxId: String,
        clientInboxId: String
    ) async {
        // Mark conversation as unread if it's not the active conversation and not from current user
        if conversationId != activeConversationId && messageInboxId != clientInboxId {
            do {
                try await localStateWriter.setUnread(true, for: conversationId)
            } catch {
                Logger.warning("Failed marking conversation as unread: \(error)")
            }
        }
    }

    // MARK: - App Lifecycle Handlers

    private func handleAppWillResignActive() {
        Logger.info("App will resign active - saving timestamp")
        lastActiveAt = Date()
    }

    private func handleAppWillTerminate() {
        Logger.info("App will terminate - saving timestamp")
        lastActiveAt = Date()
    }

    private func handleAppDidBecomeActive() {
        Logger.info("App did become active - last active was: \(lastActiveAt ?? Date())")
        // The timestamp will be used in the next sync cycle
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
