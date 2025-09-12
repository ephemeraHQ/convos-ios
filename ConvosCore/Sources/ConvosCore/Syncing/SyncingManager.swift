import Foundation
import GRDB
import UIKit
import XMTPiOS

// MARK: - Protocol

protocol SyncingManagerProtocol: Actor {
    func start(with client: AnyClientProvider, apiClient: any ConvosAPIClientProtocol)
    func stop()
}

actor SyncingManager: SyncingManagerProtocol {
    // MARK: - Properties

    private let conversationWriter: any ConversationWriterProtocol
    private let messageWriter: any IncomingMessageWriterProtocol
    private let profileWriter: any MemberProfileWriterProtocol
    private let localStateWriter: any ConversationLocalStateWriterProtocol
    private let consentStates: [ConsentState] = [.allowed]

    // Single parent task that manages everything
    private var syncTask: Task<Void, Never>?

    private var lastProcessedMessageAt: Date?
    private var activeConversationId: String?
    private var lastMemberProfileSync: [String: Date] = [:]

    // Configuration
    private let maxStreamRetries: Int = 5
    private let memberProfileSyncInterval: TimeInterval = 120.0

    // App lifecycle tracking
    private var lastActiveAt: Date? {
        get {
            let timestamp = UserDefaults.standard.double(forKey: "org.convos.SyncingManager.lastActiveTimestamp")
            return timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil
        }
        set {
            UserDefaults.standard.set(newValue?.timeIntervalSince1970 ?? 0, forKey: "org.convos.SyncingManager.lastActiveTimestamp")
        }
    }

    // MARK: - Initialization

    init(databaseWriter: any DatabaseWriter) {
        let messageWriter = IncomingMessageWriter(databaseWriter: databaseWriter)
        self.conversationWriter = ConversationWriter(
            databaseWriter: databaseWriter,
            messageWriter: messageWriter
        )
        self.messageWriter = messageWriter
        self.profileWriter = MemberProfileWriter(databaseWriter: databaseWriter)
        self.localStateWriter = ConversationLocalStateWriter(databaseWriter: databaseWriter)

        setupNotificationObservers()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Public Interface

    func start(with client: AnyClientProvider, apiClient: any ConvosAPIClientProtocol) {
        // Cancel existing sync
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            guard let self else { return }
            await withTaskGroup(of: Void.self) { group in
                // Initial sync
                await self.syncAllConversations(client: client, apiClient: apiClient)

                // Message stream with built-in retry
                group.addTask {
                    await self.runMessageStream(client: client, apiClient: apiClient)
                }

                // Conversation stream with built-in retry
                group.addTask {
                    await self.runConversationStream(client: client, apiClient: apiClient)
                }
            }
        }
    }

    func stop() {
        Logger.info("Stopping...")
        // Save timestamp for catch-up on next start
        lastActiveAt = Date()
        syncTask?.cancel()
        syncTask = nil
    }

    // MARK: - Stream Management

    private func runMessageStream(client: AnyClientProvider, apiClient: any ConvosAPIClientProtocol) async {
        var retryCount = 0

        while !Task.isCancelled && retryCount < maxStreamRetries {
            do {
                // Exponential backoff
                if retryCount > 0 {
                    let delay = TimeInterval.calculateExponentialBackoff(for: retryCount)
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

                    // Sync before restart
                    await syncAllConversationsQuick(client: client)
                }

                Logger.info("Starting message stream (attempt \(retryCount + 1)/\(maxStreamRetries))")

                // Catch up if needed
                if let lastProcessedAt = lastProcessedMessageAt {
                    await catchUpMessages(client: client, since: lastProcessedAt, apiClient: apiClient)
                }

                // Stream messages - the loop will exit when onClose is called and continuation.finish() happens
                for try await message in client.conversationsProvider.streamAllMessages(
                    type: .groups,
                    consentStates: consentStates,
                    onClose: {
                        Logger.info("Message stream closed via onClose callback")
                    }
                ) {
                    // Check cancellation
                    try Task.checkCancellation()

                    // Process message
                    await processMessage(message, client: client, apiClient: apiClient)
                }

                // Stream ended (onClose was called and continuation finished)
                retryCount += 1
                Logger.info("Message stream ended...")
            } catch is CancellationError {
                Logger.info("Message stream cancelled")
                break
            } catch {
                retryCount += 1
                Logger.error("Message stream error: \(error)")
            }
        }

        if retryCount >= maxStreamRetries {
            Logger.error("Message stream max retries reached")
        }
    }

    private func runConversationStream(client: AnyClientProvider, apiClient: any ConvosAPIClientProtocol) async {
        var retryCount = 0

        while !Task.isCancelled && retryCount < maxStreamRetries {
            do {
                if retryCount > 0 {
                    let delay = TimeInterval.calculateExponentialBackoff(for: retryCount)
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }

                Logger.info("Starting conversation stream (attempt \(retryCount + 1)/\(maxStreamRetries))")

                // Stream conversations - the loop will exit when onClose is called
                for try await conversation in client.conversationsProvider.stream(
                    type: .groups,
                    onClose: {
                        Logger.info("Conversation stream closed via onClose callback")
                    }
                ) {
                    // Check cancellation
                    try Task.checkCancellation()

                    // Process conversation
                    await processConversation(conversation, apiClient: apiClient)
                }

                // Stream ended (onClose was called and continuation finished)
                retryCount += 1
                Logger.info("Conversation stream ended, will retry...")
            } catch is CancellationError {
                Logger.info("Conversation stream cancelled")
                break
            } catch {
                retryCount += 1
                Logger.error("Conversation stream error: \(error)")
            }
        }

        if retryCount >= maxStreamRetries {
            Logger.error("Conversation stream max retries reached")
        }
    }

    // MARK: - Processing

    private func processMessage(
        _ message: DecodedMessage,
        client: AnyClientProvider,
        apiClient: any ConvosAPIClientProtocol
    ) async {
        do {
            // Find conversation
            guard let conversation = try await client.conversationsProvider.findConversation(
                conversationId: message.conversationId
            ) else {
                Logger.error("Conversation not found for message")
                return
            }

            // Sync profiles if needed
            if shouldSyncMemberProfiles(for: conversation.id) {
                await syncMemberProfiles(apiClient: apiClient, for: [conversation])
            }

            // Store conversation and message
            let dbConversation = try await conversationWriter.store(conversation: conversation)
            let result = try await messageWriter.store(message: message, for: dbConversation)
            // Update timestamp
            lastProcessedMessageAt = max(lastProcessedMessageAt ?? message.sentAt, message.sentAt)

            // Mark unread if needed
            if result.contentType.marksConversationAsUnread,
               conversation.id != activeConversationId,
               message.senderInboxId != client.inboxId {
                try await localStateWriter.setUnread(true, for: conversation.id)
            }

            Logger.info("Processed message: \(message.id)")
        } catch {
            Logger.error("Error processing message: \(error)")
        }
    }

    private func processConversation(
        _ conversation: XMTPiOS.Conversation,
        apiClient: any ConvosAPIClientProtocol
    ) async {
        do {
            // Sync member profiles
            if shouldSyncMemberProfiles(for: conversation.id) {
                await syncMemberProfiles(apiClient: apiClient, for: [conversation])
            }

            // Store with latest messages
            Logger.info("Syncing conversation: \(conversation.id)")
            try await conversationWriter.storeWithLatestMessages(conversation: conversation)
        } catch {
            Logger.error("Error processing conversation: \(error)")
        }
    }

    // MARK: - Sync Operations

    private func syncAllConversations(
        client: AnyClientProvider,
        apiClient: any ConvosAPIClientProtocol
    ) async {
        do {
            _ = try await client.conversationsProvider.syncAllConversations(consentStates: consentStates)
            // List all conversations
            let conversations = try await client.conversationsProvider.list(
                createdAfter: nil,
                createdBefore: nil,
                limit: nil,
                consentStates: consentStates
            )

            Logger.info("Syncing \(conversations.count) conversations")

            // Process in parallel using TaskGroup
            await withTaskGroup(of: Void.self) { group in
                // Store conversations
                for conversation in conversations {
                    guard case .group = conversation else { continue }

                    group.addTask { [weak self] in
                        guard let self else { return }
                        do {
                            try await self.conversationWriter.storeWithLatestMessages(
                                conversation: conversation
                            )
                        } catch {
                            Logger.error("Error storing conversation: \(error)")
                        }
                    }
                }

                // Sync profiles
                group.addTask { [weak self] in
                    guard let self else { return }
                    await self.syncMemberProfiles(apiClient: apiClient, for: conversations)
                }
            }

            // Catch up on messages if we have a last active timestamp
            if let lastActiveAt = self.lastActiveAt {
                await catchUpMessages(client: client, since: lastActiveAt, apiClient: apiClient)
                self.lastActiveAt = nil
            }

            Logger.info("Completed initial sync")
        } catch {
            Logger.error("Error syncing conversations: \(error)")
        }
    }

    private func syncAllConversationsQuick(client: AnyClientProvider) async {
        do {
            _ = try await client.conversationsProvider.syncAllConversations(consentStates: consentStates)
        } catch {
            Logger.error("Error in quick sync: \(error)")
        }
    }

    private func catchUpMessages(
        client: AnyClientProvider,
        since timestamp: Date,
        apiClient: any ConvosAPIClientProtocol
    ) async {
        do {
            let conversations = try await client.conversationsProvider.list(
                createdAfter: nil,
                createdBefore: nil,
                limit: nil,
                consentStates: consentStates
            )

            let timestampNs = timestamp.nanosecondsSince1970

            // Process catch-up in parallel
            await withTaskGroup(of: Void.self) { group in
                for conversation in conversations {
                    guard case .group = conversation else { continue }

                    group.addTask { [weak self] in
                        guard let self else { return }
                        do {
                            let messages = try await conversation.messages(
                                afterNs: timestampNs,
                                direction: .ascending
                            )

                            try Task.checkCancellation()

                            for message in messages {
                                try Task.checkCancellation()
                                await self.processMessage(message, client: client, apiClient: apiClient)
                            }

                            if !messages.isEmpty {
                                Logger.info("Caught up \(messages.count) messages for conversation")
                            }
                        } catch {
                            Logger.error("Error catching up messages: \(error)")
                        }
                    }
                }
            }
        } catch {
            Logger.error("Error in catch-up: \(error)")
        }
    }

    // MARK: - Member Profile Sync

    private func shouldSyncMemberProfiles(for conversationId: String) -> Bool {
        let now = Date()
        if let lastSync = lastMemberProfileSync[conversationId],
           now.timeIntervalSince(lastSync) < memberProfileSyncInterval {
            return false
        }
        lastMemberProfileSync[conversationId] = now
        return true
    }

    private func syncMemberProfiles(
        apiClient: any ConvosAPIClientProtocol,
        for conversations: [XMTPiOS.Conversation]
    ) async {
        // Collect member IDs
        var memberIds = Set<String>()

        for conversation in conversations {
            if let members = try? await conversation.members() {
                memberIds.formUnion(members.map { $0.inboxId })
            }
        }

        guard !memberIds.isEmpty else { return }

        // Batch fetch profiles
        let chunks = Array(memberIds).chunked(into: 50)

        await withTaskGroup(of: Void.self) { group in
            for chunk in chunks {
                group.addTask { [weak self] in
                    guard let self else { return }
                    do {
                        let batchProfiles = try await apiClient.getProfiles(for: chunk)
                        let profiles = Array(batchProfiles.profiles.values)
                        try await self.profileWriter.store(profiles: profiles)
                        Logger.info("Synced \(profiles.count) profiles")
                    } catch {
                        Logger.error("Error syncing profiles: \(error)")
                    }
                }
            }
        }
    }

    // MARK: - Mutation

    func markLastActiveAtAsNow() {
        lastActiveAt = Date()
    }

    func setActiveConversationId(_ conversationId: String?) {
        activeConversationId = conversationId
    }

    // MARK: - Notification Observers

    private nonisolated func setupNotificationObservers() {
        // Active conversation tracking
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleActiveConversationChanged),
            name: .activeConversationChanged,
            object: nil
        )

        // App lifecycle
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
    }

    @objc nonisolated private func handleActiveConversationChanged(_ notification: Notification) {
        Task {
            await setActiveConversationId(notification.userInfo?["conversationId"] as? String)
        }
    }

    @objc nonisolated private func handleAppWillResignActive() {
        Task {
            await markLastActiveAtAsNow()
        }
    }
}

// MARK: - Extensions

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
