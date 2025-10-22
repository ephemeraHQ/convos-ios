import Combine
import Foundation
import GRDB
import XMTPiOS

public struct ConversationReadyResult {
    public enum Origin {
        case created
        case joined
        case existing
    }

    public let conversationId: String
    public let origin: Origin
}

public actor ConversationStateMachine {
    enum Action {
        case create
        case validate(inviteCode: String)
        case join
        case delete
        case stop
    }

    public enum State: Equatable {
        case uninitialized
        case creating
        case validating(inviteCode: String)
        case validated(
            invite: SignedInvite,
            placeholder: ConversationReadyResult,
            inboxReady: InboxReadyResult,
            previousReadyResult: ConversationReadyResult?
        )
        case joining(invite: SignedInvite, placeholder: ConversationReadyResult)
        case ready(ConversationReadyResult)
        case deleting
        case error(Error)

        public static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.uninitialized, .uninitialized),
                 (.creating, .creating),
                 (.deleting, .deleting):
                return true
            case let (.joining(lhsInvite, _), .joining(rhsInvite, _)):
                return lhsInvite.payload.conversationToken == rhsInvite.payload.conversationToken
            case let (.validating(lhsCode), .validating(rhsCode)):
                return lhsCode == rhsCode
            case let (.validated(lhsInvite, _, lhsInbox, _), .validated(rhsInvite, _, rhsInbox, _)):
                return (lhsInvite.payload.conversationToken == rhsInvite.payload.conversationToken &&
                        lhsInbox.client.inboxId == rhsInbox.client.inboxId)
            case let (.ready(lhsResult), .ready(rhsResult)):
                return lhsResult.conversationId == rhsResult.conversationId
            default:
                return false
            }
        }
    }

    // MARK: - Properties

    private let identityStore: any KeychainIdentityStoreProtocol
    private let inboxStateManager: any InboxStateManagerProtocol
    private let databaseReader: any DatabaseReader
    private let databaseWriter: any DatabaseWriter
    private let environment: AppEnvironment

    private var currentTask: Task<Void, Never>?
    private var streamConversationsTask: Task<Void, Never>?
    private var actionQueue: [Action] = []
    private var isProcessing: Bool = false

    // Message stream for ordered message sending
    private var messageStreamContinuation: AsyncStream<String>.Continuation?
    private var messageProcessingTask: Task<Void, Never>?
    private var isMessageStreamSetup: Bool = false

    // MARK: - State Observation

    private var stateContinuations: [AsyncStream<State>.Continuation] = []
    private var _state: State = .uninitialized

    var state: State {
        get async {
            _state
        }
    }

    var stateSequence: AsyncStream<State> {
        AsyncStream { continuation in
            Task { @MainActor in
                await self.addStateContinuation(continuation)
            }
        }
    }

    private func addStateContinuation(_ continuation: AsyncStream<State>.Continuation) {
        stateContinuations.append(continuation)
        continuation.onTermination = { [weak self] _ in
            Task {
                await self?.removeStateContinuation(continuation)
            }
        }
        continuation.yield(_state)
    }

    private func emitStateChange(_ newState: State) {
        Logger.info("State changed from \(_state) to \(newState)")
        _state = newState

        // Emit to all continuations
        for continuation in stateContinuations {
            continuation.yield(newState)
        }
    }

    private func removeStateContinuation(_ continuation: AsyncStream<State>.Continuation) {
        stateContinuations.removeAll { $0 == continuation }
    }

    // MARK: - Init

    init(
        inboxStateManager: any InboxStateManagerProtocol,
        identityStore: any KeychainIdentityStoreProtocol,
        databaseReader: any DatabaseReader,
        databaseWriter: any DatabaseWriter,
        environment: AppEnvironment
    ) {
        self.inboxStateManager = inboxStateManager
        self.identityStore = identityStore
        self.databaseReader = databaseReader
        self.databaseWriter = databaseWriter
        self.environment = environment
    }

    deinit {
        streamConversationsTask?.cancel()
        currentTask?.cancel()
        messageStreamContinuation?.finish()
        messageProcessingTask?.cancel()
    }

    private func setupMessageStream() {
        guard !isMessageStreamSetup else { return }
        isMessageStreamSetup = true

        let stream = AsyncStream<String> { continuation in
            self.messageStreamContinuation = continuation
            continuation.onTermination = { [weak self] _ in
                Task { [weak self] in
                    await self?.resetMessageStream()
                }
            }
        }

        // Start a single task that processes messages in order
        messageProcessingTask = Task.detached { [weak self] in
            for await message in stream {
                guard let self else { break }
                await self.processMessage(message)
            }
            // Stream ended, reset so it can be recreated if needed
            await self?.resetMessageStream()
        }
    }

    private func resetMessageStream() {
        isMessageStreamSetup = false
        messageStreamContinuation = nil
        messageProcessingTask = nil
    }

    private func processMessage(_ text: String) async {
        do {
            // Wait for conversation to be ready if it's not
            let result = try await waitForConversationReadyResult()

            // Send the message
            let messageWriter = OutgoingMessageWriter(
                inboxStateManager: inboxStateManager,
                databaseWriter: databaseWriter,
                conversationId: result.conversationId
            )
            try await messageWriter.send(text: text)
        } catch {
            Logger.error("Error sending queued message: \(error.localizedDescription)")
        }
    }

    // MARK: - Public Actions

    func create() {
        enqueueAction(.create)
    }

    func join(inviteCode: String) {
        enqueueAction(.validate(inviteCode: inviteCode))
    }

    func sendMessage(text: String) {
        setupMessageStream()
        messageStreamContinuation?.yield(text)
    }

    func delete() {
        enqueueAction(.delete)
    }

    func stop() {
        enqueueAction(.stop)
    }

    private func waitForConversationReadyResult() async throws -> ConversationReadyResult {
        for await state in stateSequence {
            switch state {
            case .ready(let result):
                return result
            case .error(let error):
                throw error
            default:
                continue
            }
        }

        throw ConversationStateMachineError.timedOut
    }

    // MARK: - Private Action Processing

    private func enqueueAction(_ action: Action) {
        actionQueue.append(action)
        processNextAction()
    }

    private func processNextAction() {
        guard !isProcessing, !actionQueue.isEmpty else { return }

        isProcessing = true
        let action = actionQueue.removeFirst()

        currentTask = Task.detached { [weak self] in
            guard let self else { return }
            await self.processAction(action)
            await self.setProcessingComplete()
        }
    }

    private func setProcessingComplete() {
        isProcessing = false
        processNextAction()
    }

    private func processAction(_ action: Action) async {
        do {
            switch (_state, action) {
            case (.uninitialized, .create):
                try await handleCreate()
            case (.error, .create):
                handleStop()
                try await handleCreate()

            case (.uninitialized, let .validate(inviteCode)):
                try await handleValidate(inviteCode: inviteCode, previousResult: nil)
            case let (.ready(previousResult), .validate(inviteCode)):
                try await handleValidate(inviteCode: inviteCode, previousResult: previousResult)
            case let (.error, .validate(inviteCode)):
                handleStop()
                try await handleValidate(inviteCode: inviteCode, previousResult: nil)

            case (let .validated(invite, placeholder, inboxReady, previousResult), .join):
                try await handleJoin(
                    invite: invite,
                    placeholder: placeholder,
                    inboxReady: inboxReady,
                    previousReadyResult: previousResult
                )

            case (.ready, .delete), (.error, .delete):
                try await handleDelete()

            case (_, .stop):
                handleStop()

            default:
                Logger.warning("Invalid state transition: \(_state) -> \(action)")
            }
        } catch {
            Logger.error("Failed state transition \(_state) -> \(action): \(error.localizedDescription)")
            emitStateChange(.error(error))
        }
    }

    // MARK: - Action Handlers

    private func handleCreate() async throws {
        emitStateChange(.creating)

        // Request push notification permissions when user creates a conversation
        // Device is already registered (from app launch), and will be updated
        // automatically when APNS token arrives via the observer
        await PushNotificationRegistrar.requestNotificationAuthorizationIfNeeded()

        let inboxReady = try await inboxStateManager.waitForInboxReadyResult()
        Logger.info("Inbox ready, creating conversation...")

        let client = inboxReady.client

        // Create the optimistic conversation
        let optimisticConversation = try client.prepareConversation()
        let externalConversationId = optimisticConversation.id

        // Publish the conversation
        try await optimisticConversation.publish()

        // Transition directly to ready state
        emitStateChange(.ready(ConversationReadyResult(
            conversationId: externalConversationId,
            origin: .created
        )))

        // Clear unused inbox from keychain now that conversation is successfully created
        await UnusedInboxCache.shared
            .clearUnusedInbox(
                with: client.inboxId,
                databaseWriter: databaseWriter,
                databaseReader: databaseReader,
                environment: environment
            )
    }

    private func handleValidate(inviteCode: String, previousResult: ConversationReadyResult?) async throws {
        emitStateChange(.validating(inviteCode: inviteCode))
        Logger.info("Validating invite code '\(inviteCode)'")
        let signedInvite: SignedInvite
        do {
            signedInvite = try SignedInvite.fromInviteCode(inviteCode)
        } catch {
            throw ConversationStateMachineError.invalidInviteCodeFormat(inviteCode)
        }

        guard !signedInvite.hasExpired else {
            throw ConversationStateMachineError.inviteExpired
        }

        guard !signedInvite.conversationHasExpired else {
            throw ConversationStateMachineError.conversationExpired
        }

        // Recover the public key of whoever signed this invite
        let signerPublicKey: Data
        do {
            signerPublicKey = try signedInvite.recoverSignerPublicKey()
        } catch {
            throw ConversationStateMachineError.failedVerifyingSignature
        }
        Logger.info("Recovered signer's public key: \(signerPublicKey.hexEncodedString())")
        let existingConversation: Conversation? = try await databaseReader.read { db in
            try DBConversation
                .filter(DBConversation.Columns.inviteTag == signedInvite.payload.tag)
                .detailedConversationQuery()
                .fetchOne(db)?
                .hydrateConversation()
        }

        let existingIdentity: KeychainIdentity?
        if let existingConversation, let identity = try? await identityStore.identity(for: existingConversation.inboxId) {
            existingIdentity = identity
        } else {
            existingIdentity = nil
        }

        // In case cleanup failed while deleting an inbox/conversation
        if existingConversation != nil,
           existingIdentity == nil {
            Logger.warning("Found existing conversation for identity that does not exist, deleting...")
            _ = try await databaseWriter.write { db in
                try DBConversation
                    .filter(DBConversation.Columns.inviteTag == signedInvite.payload.tag)
                    .deleteAll(db)
            }
        }

        if let existingConversation, existingIdentity != nil {
            Logger.info("Found existing convo by invite tag...")
            let prevInboxReady = try await inboxStateManager.waitForInboxReadyResult()
            // Clear unused inbox since we're deleting it
            await UnusedInboxCache.shared
                .clearUnusedInbox(
                    with: prevInboxReady.client.inboxId,
                    databaseWriter: databaseWriter,
                    databaseReader: databaseReader,
                    environment: environment
                )
            try await inboxStateManager.delete()
            let inboxReady = try await inboxStateManager.reauthorize(
                inboxId: existingConversation.inboxId,
                clientId: existingConversation.clientId
            )
            if existingConversation.hasJoined {
                Logger.info("Already joined conversation... moving to ready state.")
                emitStateChange(.ready(.init(conversationId: existingConversation.id, origin: .existing)))
                await cleanUpPreviousConversationIfNeeded(
                    previousResult: previousResult,
                    newConversationId: existingConversation.id,
                    client: prevInboxReady.client,
                    apiClient: prevInboxReady.apiClient
                )
            } else {
                Logger.info("Waiting for invite approval...")
                if existingConversation.isDraft {
                    // update the placeholder with the signed invite
                    let messageWriter = IncomingMessageWriter(databaseWriter: databaseWriter)
                    let conversationWriter = ConversationWriter(
                        identityStore: identityStore,
                        databaseWriter: databaseWriter,
                        messageWriter: messageWriter
                    )
                    _ = try await conversationWriter.createPlaceholderConversation(
                        draftConversationId: existingConversation.id,
                        for: signedInvite,
                        inboxId: inboxReady.client.inboxId
                    )
                }
                emitStateChange(.validated(
                    invite: signedInvite,
                    placeholder: .init(conversationId: existingConversation.id, origin: .existing),
                    inboxReady: inboxReady,
                    previousReadyResult: previousResult
                ))
                enqueueAction(.join)
            }
        } else {
            Logger.info("Existing conversation not found. Creating placeholder...")
            Logger.info("Waiting for inbox ready result...")
            let inboxReady = try await inboxStateManager.waitForInboxReadyResult()
            let messageWriter = IncomingMessageWriter(databaseWriter: databaseWriter)
            let conversationWriter = ConversationWriter(
                identityStore: identityStore,
                databaseWriter: databaseWriter,
                messageWriter: messageWriter
            )
            let conversationId = try await conversationWriter.createPlaceholderConversation(
                draftConversationId: nil,
                for: signedInvite,
                inboxId: inboxReady.client.inboxId
            )
            let placeholder = ConversationReadyResult(conversationId: conversationId, origin: .joined)
            emitStateChange(.validated(
                invite: signedInvite,
                placeholder: placeholder,
                inboxReady: inboxReady,
                previousReadyResult: previousResult
            ))
            enqueueAction(.join)
        }
    }

    private func handleJoin(
        invite: SignedInvite,
        placeholder: ConversationReadyResult,
        inboxReady: InboxReadyResult,
        previousReadyResult: ConversationReadyResult?
    ) async throws {
        emitStateChange(.joining(invite: invite, placeholder: placeholder))

        // Request push notification permissions when user joins a conversation
        // Device is already registered (from app launch), and will be updated
        // automatically when APNS token arrives via the observer
        await PushNotificationRegistrar.requestNotificationAuthorizationIfNeeded()

        Logger.info("Requesting to join conversation...")

        let apiClient = inboxReady.apiClient
        let client = inboxReady.client

        let inviterInboxId = invite.payload.creatorInboxID
        let dm = try await client.newConversation(with: inviterInboxId)
        let text = try invite.toURLSafeSlug()
        _ = try await dm.prepare(text: text)
        try await dm.publish()

        // Clear unused inbox from keychain now that we sent the join request
        await UnusedInboxCache.shared
            .clearUnusedInbox(
                with: client.inboxId,
                databaseWriter: databaseWriter,
                databaseReader: databaseReader,
                environment: environment
            )

        // Clean up previous conversation, do this without matching the `conversationId`.
        // We don't need the created conversation during the 'joining' state and
        // want to make sure it is deleted even if the conversation never shows in
        // `streamConversationsTask`
        await self.cleanUpPreviousConversationIfNeeded(
            previousResult: previousReadyResult,
            newConversationId: nil,
            client: client,
            apiClient: apiClient
        )

        // Stream conversations to wait for the joined conversation
        streamConversationsTask = Task { [weak self] in
            guard let self else { return }
            do {
                Logger.info("Started streaming, looking for convo...")
                if let conversation = try await client.conversationsProvider
                    .stream(type: .groups, onClose: nil)
                    .first(where: {
                        guard case .group(let group) = $0 else { return false }
                        let tag = try group.inviteTag
                        return tag == invite.payload.tag
                    }) {
                    guard !Task.isCancelled else { return }

                    // This stream just waits for the conversation to show up
                    // Writing the conversation to the database and invite creation
                    // happens in `SyncingManager`

                    // Transition directly to ready state
                    await self.emitStateChange(.ready(ConversationReadyResult(
                        conversationId: conversation.id,
                        origin: .joined
                    )))
                } else {
                    Logger.error("Error waiting for conversation to join")
                    await self.emitStateChange(.error(ConversationStateMachineError.timedOut))
                }
            } catch {
                Logger.error("Error streaming conversations: \(error)")
                await self.emitStateChange(.error(error))
            }
        }
    }

    private func handleDelete() async throws {
        // For invites, we need the external conversation ID if available,
        // capture before changing state
        let conversationId: String? = switch _state {
        case .ready(let result):
            result.conversationId
        default:
            nil
        }

        emitStateChange(.deleting)

        // Cancel any ongoing tasks and stop accepting new messages
        streamConversationsTask?.cancel()
        messageStreamContinuation?.finish()

        if let conversationId {
            // Get the inbox state to access the API client for unsubscribing
            let inboxReady = try await inboxStateManager.waitForInboxReadyResult()

            try await cleanUp(
                conversationId: conversationId,
                client: inboxReady.client,
                apiClient: inboxReady.apiClient,
            )

            // Clear unused inbox from keychain now that we sent the join request
            await UnusedInboxCache.shared
                .clearUnusedInbox(
                    with: inboxReady.client.inboxId,
                    databaseWriter: databaseWriter,
                    databaseReader: databaseReader,
                    environment: environment
                )

            try await inboxStateManager.delete()
        }

        emitStateChange(.uninitialized)
    }

    private func cleanUpPreviousConversationIfNeeded(
        previousResult: ConversationReadyResult?,
        newConversationId: String?,
        client: any XMTPClientProvider,
        apiClient: any ConvosAPIClientProtocol
    ) async {
        guard let previousResult,
              previousResult.conversationId != newConversationId else {
            return
        }

        Logger.info("Cleaning up previous conversation: \(previousResult.conversationId)")
        do {
            try await cleanUp(
                conversationId: previousResult.conversationId,
                client: client,
                apiClient: apiClient,
            )
        } catch {
            Logger.error("Failed to clean up previous conversation: \(error)")
            // Continue with transition even if cleanup fails
        }
    }

    private func cleanUp(
        conversationId: String,
        client: any XMTPClientProvider,
        apiClient: any ConvosAPIClientProtocol
    ) async throws {
        // @jarod until we have self removal, we need to deny the conversation
        // so it doesn't show up in the list
        let externalConversation = try await client.conversationsProvider.findConversation(conversationId: conversationId)
        try await externalConversation?.updateConsentState(state: .denied)

        // Get clientId from keychain (privacy-preserving identifier, not XMTP installationId)
        if let identity = try? await identityStore.identity(for: client.inboxId) {
            // Unsubscribe from this conversation's push notification topic only
            // The welcome topic remains subscribed (it's inbox-level, not conversation-level).
            // Installation unregistration only happens at inbox level in InboxStateMachine.performInboxCleanup()
            let topic = conversationId.xmtpGroupTopicFormat
            do {
                try await apiClient.unsubscribeFromTopics(clientId: identity.clientId, topics: [topic])
                Logger.info("Unsubscribed from push topic: \(topic)")
            } catch {
                Logger.error("Failed unsubscribing from topic \(topic): \(error)")
                // Continue with cleanup even if unsubscribe fails
            }
        } else {
            Logger.warning("Identity not found, skipping push notification cleanup for: \(client.inboxId)")
        }

        // Always clean up database records, even if identity/clientId is missing
        try await databaseWriter.write { db in
            // Delete messages first (due to foreign key constraints)
            try DBMessage
                .filter(DBMessage.Columns.conversationId == conversationId)
                .deleteAll(db)

            // Delete conversation members
            try DBConversationMember
                .filter(DBConversationMember.Columns.conversationId == conversationId)
                .deleteAll(db)

            try ConversationLocalState
                .filter(ConversationLocalState.Columns.conversationId == conversationId)
                .deleteAll(db)

            try DBInvite
                .filter(DBInvite.Columns.conversationId == conversationId)
                .deleteAll(db)

            try DBConversation
                .filter(DBConversation.Columns.id == conversationId)
                .deleteAll(db)

            Logger.info("Cleaned up conversation data for conversationId: \(conversationId)")
        }

        // Check if we need to clean up the inbox
        try await databaseWriter.write { db in
            let conversationsCount = try DBConversation
                .filter(!DBConversation.Columns.id.like("draft-%"))
                .fetchCount(db)
            if conversationsCount == 0 {
                try DBInbox
                    .deleteOne(db, id: client.inboxId)
            }
        }
    }

    private func handleStop() {
        streamConversationsTask?.cancel()
        messageStreamContinuation?.finish()
        emitStateChange(.uninitialized)
    }

    private func subscribeToConversationTopics(
        conversationId: String,
        client: any XMTPClientProvider,
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
}

// MARK: - Display Error Protocol

public protocol DisplayError: Error {
    var title: String { get }
    var description: String { get }
}

// MARK: - Errors

public enum ConversationStateMachineError: Error {
    case failedFindingConversation
    case failedVerifyingSignature
    case stateMachineError(Error)
    case inviteExpired
    case conversationExpired
    case invalidInviteCodeFormat(String)
    case timedOut
}

extension ConversationStateMachineError: DisplayError {
    public var title: String {
        switch self {
        case .failedFindingConversation:
            return "No convo here"
        case .failedVerifyingSignature:
            return "Invalid invite"
        case .stateMachineError:
            return "Something went wrong"
        case .inviteExpired:
            return "Invite expired"
        case .conversationExpired:
            return "Convo expired"
        case .invalidInviteCodeFormat:
            return "Invalid code"
        case .timedOut:
            return "Try again"
        }
    }

    public var description: String {
        switch self {
        case .failedFindingConversation:
            return "Maybe it already exploded."
        case .failedVerifyingSignature:
            return "This invite couldn't be verified."
        case .stateMachineError(let error):
            return error.localizedDescription
        case .inviteExpired:
            return "This invite has expired."
        case .conversationExpired:
            return "This convo has expired."
        case .invalidInviteCodeFormat:
            return "This code is not valid."
        case .timedOut:
            return "Joining the convo failed."
        }
    }
}
