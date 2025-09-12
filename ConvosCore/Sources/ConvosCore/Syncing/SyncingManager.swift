import Foundation
import GRDB
import UIKit
import XMTPiOS

protocol SyncingManagerProtocol {
    func start(with client: AnyClientProvider,
               apiClient: any ConvosAPIClientProtocol)
    func stop() async
}

final class SyncingManager: SyncingManagerProtocol {
    // MARK: - Thread-Safe State Management
    private actor State {
        var listConversationsTask: Task<Void, Never>?
        var streamMessagesTask: Task<Void, Never>?
        var streamConversationsTask: Task<Void, Never>?
        var syncMemberProfilesTasks: [Task<Void, Error>] = []

        // Track last sync times for member profiles per conversation
        var lastMemberProfileSync: [String: Date] = [:]

        // Track when the last message was processed
        var lastProcessedMessageAt: Date?

        // Track the currently active conversation
        var activeConversationId: String?

        func updateActiveConversationId(_ id: String?) {
            activeConversationId = id
        }

        func updateLastProcessedMessageAt(_ date: Date) {
            lastProcessedMessageAt = max(lastProcessedMessageAt ?? date, date)
        }

        func shouldSyncMemberProfile(for conversationId: String, interval: TimeInterval) -> Bool {
            let now = Date()
            if let lastSync = lastMemberProfileSync[conversationId],
               now.timeIntervalSince(lastSync) < interval {
                return false
            }
            lastMemberProfileSync[conversationId] = now
            return true
        }

        func addSyncMemberProfileTask(_ task: Task<Void, Error>) {
            syncMemberProfilesTasks.append(task)

            // Create a cleanup task that removes the task from the array when it completes
            Task {
                // Wait for the task to complete (successfully or with error)
                _ = try? await task.value

                // Remove the completed task from the array
                syncMemberProfilesTasks.removeAll { $0 == task }
            }
        }

        func clearTasks() {
            listConversationsTask?.cancel()
            listConversationsTask = nil
            streamMessagesTask?.cancel()
            streamMessagesTask = nil
            streamConversationsTask?.cancel()
            streamConversationsTask = nil
            syncMemberProfilesTasks.forEach { $0.cancel() }
            syncMemberProfilesTasks.removeAll()
        }

        func setListConversationsTask(_ task: Task<Void, Never>?) {
            listConversationsTask = task
        }

        func setStreamMessagesTask(_ task: Task<Void, Never>?) {
            streamMessagesTask = task
        }

        func setStreamConversationsTask(_ task: Task<Void, Never>?) {
            streamConversationsTask = task
        }

        // Atomic check-and-set methods to prevent race conditions
        func startStreamMessagesTaskIfInactive(_ task: Task<Void, Never>) -> Bool {
            // Check if already active
            if let existingTask = streamMessagesTask, !existingTask.isCancelled {
                task.cancel() // Cancel the new task since we won't use it
                return false
            }
            // Set the new task atomically
            streamMessagesTask = task
            return true
        }

        func startStreamConversationsTaskIfInactive(_ task: Task<Void, Never>) -> Bool {
            // Check if already active
            if let existingTask = streamConversationsTask, !existingTask.isCancelled {
                task.cancel() // Cancel the new task since we won't use it
                return false
            }
            // Set the new task atomically
            streamConversationsTask = task
            return true
        }

        func isStreamTaskActive(_ streamType: StreamType) -> Bool {
            let task: Task<Void, Never>?
            switch streamType {
            case .messages:
                task = streamMessagesTask
            case .conversations:
                task = streamConversationsTask
            }
            guard let task else { return false }
            return !task.isCancelled
        }

        func isStreamTaskCancelled(_ streamType: StreamType) -> Bool {
            let task: Task<Void, Never>?
            switch streamType {
            case .messages:
                task = streamMessagesTask
            case .conversations:
                task = streamConversationsTask
            }
            return task?.isCancelled ?? true
        }
    }

    // MARK: - Properties
    private let state: State = State()
    private let conversationWriter: any ConversationWriterProtocol
    private let messageWriter: any IncomingMessageWriterProtocol
    private let profileWriter: any MemberProfileWriterProtocol
    private let localStateWriter: any ConversationLocalStateWriterProtocol
    private let consentStates: [ConsentState] = [.allowed]
    private let memberProfileSyncInterval: TimeInterval = 10 // seconds

    // Track when the app was last active (for connectivity changes)
    // This uses UserDefaults which is thread-safe, so doesn't need to be in the actor
    private var lastActiveAt: Date? {
        get {
            let timestamp = UserDefaults.standard.double(forKey: lastActiveTimestampKey)
            guard timestamp > 0 else {
                return nil
            }
            return Date(timeIntervalSince1970: timestamp)
        }
        set {
            UserDefaults.standard.set(newValue?.timeIntervalSince1970 ?? 0, forKey: lastActiveTimestampKey)
        }
    }
    private let lastActiveTimestampKey: String = "org.convos.SyncingManager.lastActiveTimestamp"

    // Notification observers (kept outside actor for simpler lifecycle management)
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
                guard let self = self else { return }
                let conversationId = notification.userInfo?["conversationId"] as? String
                Task {
                    await self.state.updateActiveConversationId(conversationId)
                }
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
        Task {
            let task = Task { [weak self] in
                guard let self = self else { return }
                await self.syncAllConversations(client: client, apiClient: apiClient)
            }
            await state.setListConversationsTask(task)
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
            await syncMemberProfiles(apiClient: apiClient, for: conversations)

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

    func stop() async {
        // Save the current timestamp when stopping
        lastActiveAt = Date()
        await state.clearTasks()
    }

    // MARK: - Private

    private let maxStreamRetries: Int = 5

    enum StreamType {
        case messages
        case conversations

        var name: String {
            switch self {
            case .messages: return "Messages"
            case .conversations: return "Conversations"
            }
        }
    }

    private func startMessageStream(client: AnyClientProvider, apiClient: any ConvosAPIClientProtocol, retryCount: Int = 0) {
        Task {
            guard retryCount < maxStreamRetries else {
                Logger.error("Messages stream max retries (\(maxStreamRetries)) reached for inbox: \(client.inboxId). Giving up.")
                return
            }

            // Create the task first, then atomically check-and-set
            let task = Task { [weak self] in
                do {
                    guard let self else { return }
                    try await self.processMessageStream(client: client, apiClient: apiClient, retryCount: retryCount)
                } catch {
                    await self?.handleMessageStreamError(
                        error: error,
                        client: client,
                        apiClient: apiClient,
                        retryCount: retryCount
                    )
                }
            }

            // Atomic check-and-set to prevent race conditions
            guard await state.startStreamMessagesTaskIfInactive(task) else {
                Logger.info("Messages stream already active, skipping start")
                return
            }

            Logger.info("Starting messages stream for inbox: \(client.inboxId) (retry: \(retryCount))")
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
        if let lastProcessedMessageAt = await state.lastProcessedMessageAt {
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
            await syncMemberProfiles(apiClient: apiClient, for: conversation)
            let dbConversation = try await conversationWriter.store(conversation: conversation)
            let result = try await messageWriter.store(message: message, for: dbConversation)

            // Update the last processed message timestamp
            await state.updateLastProcessedMessageAt(message.sentAt)

            // Mark conversation as unread if needed
            await markConversationUnreadIfNeeded(
                for: result,
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
            streamType: .messages,
            client: client,
            apiClient: apiClient,
            retryCount: retryCount
        )
    }

    private func handleMessageStreamError(error: Error, client: AnyClientProvider, apiClient: any ConvosAPIClientProtocol, retryCount: Int) async {
        Logger.error("Error streaming all messages: \(error)")
        scheduleStreamRetry(
            streamType: .messages,
            client: client,
            apiClient: apiClient,
            retryCount: retryCount
        )
    }

    private func scheduleStreamRetry(
        streamType: StreamType,
        client: AnyClientProvider,
        apiClient: any ConvosAPIClientProtocol,
        retryCount: Int
    ) {
        Task {
            // Only check if the stream task itself was cancelled, not the current context
            guard await !state.isStreamTaskCancelled(streamType) else {
                Logger.info("\(streamType.name) stream task was cancelled, not restarting")
                return
            }

            let nextRetry = retryCount + 1
            Logger.warning("\(streamType.name) stream closed for inboxId: \(client.inboxId). Restarting (retry \(nextRetry)/\(maxStreamRetries))...")

            // Clear the task reference before restarting to avoid race conditions
            switch streamType {
            case .messages:
                await state.setStreamMessagesTask(nil)
                startMessageStream(client: client, apiClient: apiClient, retryCount: nextRetry)
            case .conversations:
                await state.setStreamConversationsTask(nil)
                startConversationStream(client: client, apiClient: apiClient, retryCount: nextRetry)
            }
        }
    }

    // These methods have been moved into the State actor
    // and are accessed through state.isStreamTaskActive() and state.isStreamTaskCancelled()

    private func startConversationStream(client: AnyClientProvider, apiClient: any ConvosAPIClientProtocol, retryCount: Int = 0) {
        Task {
            guard retryCount < maxStreamRetries else {
                Logger.error("Conversations stream max retries (\(maxStreamRetries)) reached for inbox: \(client.inboxId). Giving up.")
                return
            }

            // Create the task first, then atomically check-and-set
            let task = Task { [weak self] in
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
                        await self.syncMemberProfiles(apiClient: apiClient, for: [conversation])
                        Logger.info("Syncing conversation with id: \(conversation.id)")
                        try await self.conversationWriter.storeWithLatestMessages(conversation: conversation)
                    }
                } catch {
                    await self.handleConversationStreamError(error: error, client: client, apiClient: apiClient, retryCount: retryCount)
                }
            }

            // Atomic check-and-set to prevent race conditions
            guard await state.startStreamConversationsTaskIfInactive(task) else {
                Logger.info("Conversations stream already active, skipping start")
                return
            }

            Logger.info("Starting conversations stream for inbox: \(client.inboxId) (retry: \(retryCount))")
        }
    }

    private func scheduleConversationStreamRetry(client: AnyClientProvider, apiClient: any ConvosAPIClientProtocol, retryCount: Int) {
        scheduleStreamRetry(
            streamType: .conversations,
            client: client,
            apiClient: apiClient,
            retryCount: retryCount
        )
    }

    private func handleConversationStreamError(error: Error, client: AnyClientProvider, apiClient: any ConvosAPIClientProtocol, retryCount: Int) async {
        Logger.error("Error streaming conversations: \(error)")
        scheduleStreamRetry(
            streamType: .conversations,
            client: client,
            apiClient: apiClient,
            retryCount: retryCount
        )
    }

    private func syncMemberProfiles(
        apiClient: any ConvosAPIClientProtocol,
        for conversation: XMTPiOS.Conversation
    ) async {
        let conversationId = conversation.id
        let shouldSync = await state.shouldSyncMemberProfile(for: conversationId, interval: memberProfileSyncInterval)
        if shouldSync {
            await syncMemberProfiles(apiClient: apiClient, for: [conversation])
        }
    }

    private func syncMemberProfiles(
        apiClient: any ConvosAPIClientProtocol,
        for conversations: [XMTPiOS.Conversation]
    ) async {
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
                            Logger.info("Starting batch profiles update...")
                            let batchProfiles = try await apiClient.getProfiles(for: chunk)
                            let profiles = Array(batchProfiles.profiles.values)
                            try await profileWriter.store(profiles: profiles)
                        } catch {
                            Logger.error("Error syncing member profiles: \(error)")
                            throw error
                        }
                    }
                    await state.addSyncMemberProfileTask(chunkTask)
                }
            } catch {
                Logger.error("Error syncing member profiles: \(error)")
                throw error
            }
        }
        await state.addSyncMemberProfileTask(syncProfilesTask)
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
                let result = try await messageWriter.store(message: message, for: dbConversation)

                // Update last processed message timestamp
                await state.updateLastProcessedMessageAt(message.sentAt)

                // Mark conversation as unread if needed
                await markConversationUnreadIfNeeded(
                    for: result,
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
        for result: IncomingMessageWriterResult,
        conversationId: String,
        messageInboxId: String,
        clientInboxId: String
    ) async {
        guard result.contentType.marksConversationAsUnread else { return }
        // Mark conversation as unread if it's not the active conversation and not from current user
        let activeConversationId = await state.activeConversationId
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
