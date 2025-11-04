import Foundation
import GRDB
import XMTPiOS

// MARK: - Protocol

public protocol SyncingManagerProtocol: Actor {
    func start(with client: AnyClientProvider, apiClient: any ConvosAPIClientProtocol)
    func stop()
}

/// Manages real-time synchronization of conversations and messages
///
/// SyncingManager coordinates continuous synchronization between the local database
/// and XMTP network. It handles:
/// - Initial sync of all conversations and messages
/// - Real-time streaming of new conversations and messages
/// - Processing join requests via DMs
/// - Managing conversation consent states
/// - Push notification topic subscriptions
/// - Exponential backoff retry logic for network failures
///
/// The manager maintains separate streams for conversations and messages with
/// automatic retry and backoff handling.
actor SyncingManager: SyncingManagerProtocol {
    // MARK: - Properties

    private let identityStore: any KeychainIdentityStoreProtocol
    private let streamProcessor: any StreamProcessorProtocol
    private let profileWriter: any MemberProfileWriterProtocol
    private let joinRequestsManager: any InviteJoinRequestsManagerProtocol
    private let consentStates: [ConsentState] = [.allowed, .unknown]
    private var messageStreamTask: Task<Void, Never>?
    private var conversationStreamTask: Task<Void, Never>?

    // UserDefaults key prefix for last sync timestamp
    private static let lastSyncedAtKeyPrefix: String = "convos.syncing.lastSyncedAt"

    // Single parent task that manages everything
    private var syncTask: Task<Void, Never>?

    private var activeConversationId: String?

    // Notification handling
    private var notificationObservers: [NSObjectProtocol] = []
    private var notificationTask: Task<Void, Never>?

    // MARK: - Initialization

    init(identityStore: any KeychainIdentityStoreProtocol,
         databaseWriter: any DatabaseWriter,
         databaseReader: any DatabaseReader,
         deviceRegistrationManager: (any DeviceRegistrationManagerProtocol)? = nil) {
        self.identityStore = identityStore
        self.streamProcessor = StreamProcessor(
            identityStore: identityStore,
            databaseWriter: databaseWriter,
            databaseReader: databaseReader,
            deviceRegistrationManager: deviceRegistrationManager
        )
        self.profileWriter = MemberProfileWriter(databaseWriter: databaseWriter)
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

        guard syncTask == nil else {
            Logger.info("Sync already in progress, ignoring redundant start() call")
            return
        }

        // Start the streams first
        messageStreamTask?.cancel()
        messageStreamTask = Task { [weak self] in
            guard let self else { return }
            await self.runMessageStream(client: client, apiClient: apiClient)
        }
        conversationStreamTask?.cancel()
        conversationStreamTask = Task { [weak self] in
            guard let self else { return }
            await self.runConversationStream(client: client, apiClient: apiClient)
        }

        // Create sync task
        syncTask = Task { [weak self] in
            guard let self else { return }

            // Capture sync start time first
            let syncStartTime = Date()

            // Get the last sync time for logging and join requests
            let lastSyncedAt = await self.getLastSyncedAt(for: client.inboxId)
            if let lastSyncedAt {
                Logger.info("Starting, last synced \(lastSyncedAt.relativeShort()) ago...")
            } else {
                Logger.info("Syncing for the first time...")
            }

            // Perform the initial sync
            do {
                let count = try await client.conversationsProvider.syncAllConversations(consentStates: consentStates)
                Logger.info("syncAllConversations returned count: \(count)")

                // we need to list all the conversations that have been updated since `lastSyncedAt` and then list
                // messages since `lastSyncedAt`, then process the conversation + messages
                // this is a band aid fix until the issue with streams is resolved
                do {
                    let updatedConversations = try await client.conversationsProvider
                        .listGroups(
                            createdAfterNs: nil,
                            createdBeforeNs: nil,
                            lastActivityAfterNs: lastSyncedAt?.nanosecondsSince1970,
                            lastActivityBeforeNs: nil,
                            limit: nil,
                            consentStates: consentStates,
                            orderBy: .lastActivity
                        )
                    Logger.info("Found \(updatedConversations.count) conversations since last sync, processing...")
                    try await withThrowingTaskGroup { [weak self] group in
                        for conversation in updatedConversations {
                            group.addTask {
                                guard let self else { return }
                                try await self.streamProcessor.processConversation(
                                    conversation,
                                    client: client,
                                    apiClient: apiClient
                                )
                            }
                        }
                        for try await _ in group {
                            // log completion
                        }
                    }
                } catch {
                    Logger.error("Error catching up on missed conversation updates: \(error.localizedDescription)")
                    throw error
                }

                // @jarodl we won't need this once the issue with messages in the streams not re-playing
                // is fixed
                _ = await joinRequestsManager.processJoinRequests(since: lastSyncedAt, client: client)

                // Only update timestamp after successful sync
                await self.setLastSyncedAt(syncStartTime, for: client.inboxId)
            } catch {
                Logger.error("Error syncing all conversations: \(error.localizedDescription)")
                // attempt to process join requests anyway
                _ = await joinRequestsManager.processJoinRequests(since: lastSyncedAt, client: client)
                // Don't update timestamp on failure - keep the old one
            }

            // Clean up sync task reference
            await self.cleanupSyncTask()
        }
    }

    func stop() {
        Logger.info("Stopping...")

        // Cancel sync tasks
        messageStreamTask?.cancel()
        messageStreamTask = nil
        conversationStreamTask?.cancel()
        conversationStreamTask = nil
        syncTask?.cancel()
        syncTask = nil

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
                    await streamProcessor.processMessage(
                        message,
                        client: client,
                        apiClient: apiClient,
                        activeConversationId: activeConversationId
                    )
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
                    guard case .group(let conversation) = conversation else {
                        continue
                    }

                    // Check cancellation
                    try Task.checkCancellation()

                    // Reset retry count after first successful conversation (stream is healthy)
                    if isFirstConversation {
                        retryCount = 0
                        isFirstConversation = false
                    }

                    // Process conversation
                    try await streamProcessor.processConversation(
                        conversation,
                        client: client,
                        apiClient: apiClient
                    )
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

    // MARK: - Mutation

    func setActiveConversationId(_ conversationId: String?) {
        // Update the active conversation
        activeConversationId = conversationId
    }

    private func cleanupSyncTask() {
        syncTask = nil
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
