import Foundation
import GRDB
import XMTPiOS

// MARK: - Protocol

public protocol SyncingManagerProtocol: Actor {
    func start(with client: AnyClientProvider, apiClient: any ConvosAPIClientProtocol)
    func stop() async
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
    }

    func stop() async {
        Log.info("Stopping...")

        // Cancel and wait for sync tasks to complete
        // This ensures no database operations are in-flight before cleanup
        if let task = messageStreamTask {
            task.cancel()
            _ = await task.value
            messageStreamTask = nil
        }

        if let task = conversationStreamTask {
            task.cancel()
            _ = await task.value
            conversationStreamTask = nil
        }

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

                Log.info("Starting message stream (attempt \(retryCount + 1))")

                // Stream messages - the loop will exit when onClose is called and continuation.finish() happens
                var isFirstMessage = true
                for try await message in client.conversationsProvider.streamAllMessages(
                    type: .all,
                    consentStates: consentStates,
                    onClose: {
                        Log.info("Message stream closed via onClose callback")
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
                Log.info("Message stream ended...")
            } catch is CancellationError {
                Log.info("Message stream cancelled")
                break
            } catch {
                retryCount += 1
                Log.error("Message stream error: \(error)")
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

                Log.info("Starting conversation stream (attempt \(retryCount + 1))")

                // Stream conversations - the loop will exit when onClose is called
                var isFirstConversation = true
                for try await conversation in client.conversationsProvider.stream(
                    type: .groups,
                    onClose: {
                        Log.info("Conversation stream closed via onClose callback")
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
                Log.info("Conversation stream ended, will retry...")
            } catch is CancellationError {
                Log.info("Conversation stream cancelled")
                break
            } catch {
                retryCount += 1
                Log.error("Conversation stream error: \(error)")
            }
        }
    }

    // MARK: - Mutation

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
    }
}
