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

    private let identityStore: any KeychainIdentityStoreProtocol
    private let conversationWriter: any ConversationWriterProtocol
    private let messageWriter: any IncomingMessageWriterProtocol
    private let profileWriter: any MemberProfileWriterProtocol
    private let localStateWriter: any ConversationLocalStateWriterProtocol
    private let joinRequestsManager: any InviteJoinRequestsManagerProtocol
    private let consentStates: [ConsentState] = [.allowed, .unknown]

    // UserDefaults key prefix for last sync timestamp
    private static let lastSyncedAtKeyPrefix: String = "convos.syncing.lastSyncedAt"

    // Single parent task that manages everything
    private var syncTask: Task<Void, Never>?

    // Track if a sync is currently in progress
    private var isSyncing: Bool = false

    private var activeConversationId: String?

    // Notification handling
    private var notificationObservers: [NSObjectProtocol] = []
    private var notificationTask: Task<Void, Never>?

    // MARK: - Initialization

    init(identityStore: any KeychainIdentityStoreProtocol,
         databaseWriter: any DatabaseWriter,
         databaseReader: any DatabaseReader) {
        self.identityStore = identityStore
        let messageWriter = IncomingMessageWriter(databaseWriter: databaseWriter)
        self.conversationWriter = ConversationWriter(
            identityStore: identityStore,
            databaseWriter: databaseWriter,
            messageWriter: messageWriter
        )
        self.messageWriter = messageWriter
        self.profileWriter = MemberProfileWriter(databaseWriter: databaseWriter)
        self.localStateWriter = ConversationLocalStateWriter(databaseWriter: databaseWriter)
        self.joinRequestsManager = InviteJoinRequestsManager(
            identityStore: identityStore,
            databaseReader: databaseReader
        )
    }

    deinit {
        // Clean up tasks
        notificationTask?.cancel()

        // Remove observers (safe to do from deinit)
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Public Interface

    func start(with client: AnyClientProvider, apiClient: any ConvosAPIClientProtocol) {
        // Setup notifications if not already done
        if notificationObservers.isEmpty {
            setupNotificationObservers()
        }

        // If already syncing, just cancel and restart
        // This prevents race conditions with multiple rapid start() calls
        if isSyncing {
            Logger.info("Sync already in progress, restarting...")
        }

        // Cancel existing sync
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            guard let self else { return }

            // Mark as syncing
            await self.setSyncing(true)

            // Ensure we clean up the syncing flag when done
            defer {
                Task { [weak self] in
                    await self?.setSyncing(false)
                }
            }

            // Save the sync start time
            let lastSyncedAt = await self.getLastSyncedAt(for: client.inboxId)
            if let lastSyncedAt {
                Logger.info("Starting, last synced \(lastSyncedAt.relativeShort()) ago...")
            } else {
                Logger.info("Syncing for the first time...")
            }

            // Perform the initial sync
            let syncStartTime = Date()

            do {
                _ = try await client.conversationsProvider.syncAllConversations(consentStates: consentStates)
                // Only update timestamp after successful sync
                await self.setLastSyncedAt(syncStartTime, for: client.inboxId)
            } catch {
                Logger.error("Error syncing all conversations: \(error.localizedDescription)")
                // Don't update timestamp on failure - keep the old one
            }

            _ = await joinRequestsManager.processJoinRequests(since: lastSyncedAt, client: client)

            await withTaskGroup(of: Void.self) { group in
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

        // Cancel sync tasks
        syncTask?.cancel()
        syncTask = nil

        // Clear syncing flag
        isSyncing = false

        activeConversationId = nil

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
                }

                Logger.info("Starting message stream (attempt \(retryCount + 1))")

                // Stream messages - the loop will exit when onClose is called and continuation.finish() happens
                var isFirstMessage = true
                for try await message in client.conversationsProvider.streamAllMessages(
                    type: .all,
                    consentStates: consentStates,
                    onClose: {
                        Logger.info("Message stream closed via onClose callback")
                    }
                ) {
                    // Check cancellation
                    try Task.checkCancellation()

                    // Reset retry count after first successful message (stream is healthy)
                    if isFirstMessage {
                        retryCount = 0
                        isFirstMessage = false
                    }

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

                Logger.info("Starting conversation stream (attempt \(retryCount + 1))")

                // Stream conversations - the loop will exit when onClose is called
                var isFirstConversation = true
                for try await conversation in client.conversationsProvider.stream(
                    type: .groups,
                    onClose: {
                        Logger.info("Conversation stream closed via onClose callback")
                    }
                ) {
                    // Check cancellation
                    try Task.checkCancellation()

                    // Reset retry count after first successful conversation (stream is healthy)
                    if isFirstConversation {
                        retryCount = 0
                        isFirstConversation = false
                    }

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

    /// Checks if a conversation should be processed based on its consent state.
    /// If consent is unknown but there's an outgoing join request, updates consent to allowed.
    /// - Parameters:
    ///   - conversation: The conversation to check
    ///   - client: The client provider
    /// - Returns: True if the conversation has allowed consent and should be processed
    private func shouldProcessConversation(
        _ conversation: XMTPiOS.Conversation,
        client: AnyClientProvider
    ) async throws -> Bool {
        var consentState = try conversation.consentState()

        if consentState == .unknown {
            let hasOutgoingJoinRequest = try await joinRequestsManager.hasOutgoingJoinRequest(
                for: conversation,
                client: client
            )

            if hasOutgoingJoinRequest {
                try await conversation.updateConsentState(state: .allowed)
                consentState = try conversation.consentState()
            }
        }

        return consentState == .allowed
    }

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

            switch conversation {
            case .dm:
                _ = try await joinRequestsManager.processJoinRequest(
                    message: message,
                    client: client
                )
            case .group:
                guard try await shouldProcessConversation(conversation, client: client) else { return }

                // Store conversation and message
                let dbConversation = try await conversationWriter.store(conversation: conversation)
                let result = try await messageWriter.store(message: message, for: dbConversation)

                // Mark unread if needed
                if result.contentType.marksConversationAsUnread,
                   conversation.id != activeConversationId,
                   message.senderInboxId != client.inboxId {
                    try await localStateWriter.setUnread(true, for: conversation.id)
                }
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
            guard case .group = conversation else {
                Logger.info("Streamed DM, ignoring...")
                return
            }

            guard try await shouldProcessConversation(conversation, client: client) else { return }

            let creatorInboxId = try await conversation.creatorInboxId
            if creatorInboxId == client.inboxId,
               case .group(let group) = conversation {
                // we created the conversaiton, update permissions and set inviteTag
                try await group.updateAddMemberPermission(newPermissionOption: .allow)
                try await group.updateInviteTag()
            }

            // clean up the previous conversation?

            Logger.info("Syncing conversation: \(conversation.id)")
            try await conversationWriter.storeWithLatestMessages(conversation: conversation)

            // Subscribe to push notifications
            await subscribeToConversationTopics(
                conversationId: conversation.id,
                client: client,
                apiClient: apiClient,
                context: "on stream"
            )
        } catch {
            Logger.error("Error processing conversation: \(error)")
        }
    }

    // MARK: - Mutation

    func setActiveConversationId(_ conversationId: String?) {
        // Update the active conversation
        activeConversationId = conversationId
    }

    private func setSyncing(_ syncing: Bool) {
        isSyncing = syncing
    }

    // MARK: - Push Notifications

    private func subscribeToConversationTopics(
        conversationId: String,
        client: AnyClientProvider,
        apiClient: any ConvosAPIClientProtocol,
        context: String
    ) async {
        let conversationTopic = conversationId.xmtpGroupTopicFormat
        let welcomeTopic = client.installationId.xmtpWelcomeTopicFormat

        guard let identity = try? await identityStore.identity(for: client.inboxId) else {
            Logger.warning("Identity not found, skipping push notification subscription")
            return
        }

        do {
            let deviceId = DeviceInfo.deviceIdentifier
            try await apiClient.subscribeToTopics(
                deviceId: deviceId,
                clientId: identity.clientId,
                topics: [conversationTopic, welcomeTopic]
            )
            Logger.info("Subscribed to push topics \(context): \(conversationTopic), \(welcomeTopic)")
        } catch {
            Logger.error("Failed subscribing to topics \(context): \(error)")
        }
    }

    // MARK: - Last Synced At

    private func getLastSyncedAt(for inboxId: String) -> Date? {
        let key = "\(Self.lastSyncedAtKeyPrefix).\(inboxId)"
        return UserDefaults.standard.object(forKey: key) as? Date
    }

    private func setLastSyncedAt(_ date: Date?, for inboxId: String) {
        let key = "\(Self.lastSyncedAtKeyPrefix).\(inboxId)"
        UserDefaults.standard.set(date, forKey: key)
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
    }
}
