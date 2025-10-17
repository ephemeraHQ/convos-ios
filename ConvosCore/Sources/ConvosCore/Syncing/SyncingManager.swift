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
    private let memberProfileSyncInterval: TimeInterval = 120.0
    private let activeConversationProfileSyncInterval: TimeInterval = 10.0 // Sync more frequently for active conversation

    // Notification handling
    private var notificationObservers: [NSObjectProtocol] = []
    private var notificationTask: Task<Void, Never>?

    // Active conversation profile sync
    private var activeConversationProfileTask: Task<Void, Never>?
    private weak var currentClient: AnyClientProvider?
    private weak var currentApiClient: (any ConvosAPIClientProtocol)?

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

    init(identityStore: any KeychainIdentityStoreProtocol,
         databaseWriter: any DatabaseWriter) {
        let messageWriter = IncomingMessageWriter(databaseWriter: databaseWriter)
        self.conversationWriter = ConversationWriter(
            identityStore: identityStore,
            databaseWriter: databaseWriter,
            messageWriter: messageWriter
        )
        self.messageWriter = messageWriter
        self.profileWriter = MemberProfileWriter(databaseWriter: databaseWriter)
        self.localStateWriter = ConversationLocalStateWriter(databaseWriter: databaseWriter)
    }

    deinit {
        // Clean up tasks
        notificationTask?.cancel()
        activeConversationProfileTask?.cancel()

        // Remove observers (safe to do from deinit)
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Public Interface

    func start(with client: AnyClientProvider, apiClient: any ConvosAPIClientProtocol) {
        // Store references for profile syncing
        currentClient = client
        currentApiClient = apiClient

        // Setup notifications if not already done
        if notificationObservers.isEmpty {
            setupNotificationObservers()
        }

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

        // Cancel sync tasks
        syncTask?.cancel()
        syncTask = nil

        // Cancel active conversation profile sync
        activeConversationProfileTask?.cancel()
        activeConversationProfileTask = nil
        activeConversationId = nil

        // Clear client references
        currentClient = nil
        currentApiClient = nil

        // Clean up notification observers
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        notificationObservers.removeAll()
    }

    // MARK: - Stream Management

    private func runMessageStream(client: AnyClientProvider, apiClient: any ConvosAPIClientProtocol) async {
        var retryCount = 0

        while !Task.isCancelled {
            do {
                // Exponential backoff
                if retryCount > 0 {
                    let delay = TimeInterval.calculateExponentialBackoff(for: retryCount)
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

                    // Sync before restart
                    await syncAllConversationsQuick(client: client)
                }

                Logger.info("Starting message stream (attempt \(retryCount + 1)")

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
    }

    private func runConversationStream(client: AnyClientProvider, apiClient: any ConvosAPIClientProtocol) async {
        var retryCount = 0

        while !Task.isCancelled {
            do {
                if retryCount > 0 {
                    let delay = TimeInterval.calculateExponentialBackoff(for: retryCount)
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }

                Logger.info("Starting conversation stream (attempt \(retryCount + 1)")

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
                    await processConversation(conversation, client: client, apiClient: apiClient)
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
        client: AnyClientProvider,
        apiClient: any ConvosAPIClientProtocol
    ) async {
        do {
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

    // MARK: - Mutation

    func markLastActiveAtAsNow() {
        lastActiveAt = Date()
    }

    func setActiveConversationId(_ conversationId: String?) {
        // Update the active conversation
        activeConversationId = conversationId
    }

    // MARK: - Notification Observers

    private func setupNotificationObservers() {
        let activeConversationObserver = NotificationCenter.default.addObserver(
            forName: .activeConversationChanged,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let self else { return }
            Task { [weak self] in
                guard let self else { return }
                await self.setActiveConversationId(notification.userInfo?["conversationId"] as? String)
            }
        }
        notificationObservers.append(activeConversationObserver)

        let appLifecycleObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            Task { [weak self] in
                guard let self else { return }
                await self.markLastActiveAtAsNow()
            }
        }
        notificationObservers.append(appLifecycleObserver)
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
