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

        let inboxReady = try await inboxStateManager.waitForInboxReadyResult()
        Logger.info("Inbox ready, creating conversation...")

        let client = inboxReady.client
        let apiClient = inboxReady.apiClient

        // Create the optimistic conversation
        let optimisticConversation = try client.prepareConversation()
        let externalConversationId = optimisticConversation.id

        // Publish the conversation
        try await optimisticConversation.publish()

        // Fetch the created conversation
        guard let createdConversation = try await client.conversation(with: externalConversationId) else {
            throw ConversationStateMachineError.failedFindingConversation
        }

        guard case .group(let group) = createdConversation else {
            throw ConversationStateMachineError.failedFindingConversation
        }

        // Update permissions for group conversations
        try await group.updateAddMemberPermission(newPermissionOption: .allow)
        try await group.updateInviteTag()

        // Store the conversation
        let messageWriter = IncomingMessageWriter(databaseWriter: databaseWriter)
        let conversationWriter = ConversationWriter(
            identityStore: identityStore,
            databaseWriter: databaseWriter,
            messageWriter: messageWriter
        )
        let dbConversation = try await conversationWriter.store(conversation: createdConversation)

        // Create invite
        let inviteWriter = InviteWriter(identityStore: identityStore, databaseWriter: databaseWriter)
        _ = try await inviteWriter.generate(for: dbConversation, expiresAt: nil)

        // Subscribe to push notifications
        let topic = externalConversationId.xmtpGroupTopicFormat
        do {
            try await apiClient.subscribeToTopics(installationId: client.installationId, topics: [topic])
            Logger.info("Subscribed to push topic: \(topic)")
        } catch {
            Logger.error("Failed subscribing to topic \(topic): \(error)")
        }

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

        if let existingConversation {
            Logger.info("Found existing convo by invite tag...")
            let prevInboxReady = try await inboxStateManager.waitForInboxReadyResult()
            try await inboxStateManager.delete()
            let inboxReady = try await inboxStateManager.reauthorize(inboxId: existingConversation.inboxId)
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

        Logger.info("Requesting to join conversation...")

        let apiClient = inboxReady.apiClient
        let client = inboxReady.client

        let inviterInboxId = invite.payload.creatorInboxID
        let dm = try await client.newConversation(with: inviterInboxId)
        let text = try invite.toURLSafeSlug()
        _ = try await dm.prepare(text: text)
        try await dm.publish()

        // Stream conversations to wait for the joined conversation
        streamConversationsTask = Task { [weak self] in
            guard let self else { return }
            do {
                Logger.info("Started streaming, looking for convo...")
                if let conversation = try await client.conversationsProvider
                    .stream(type: .groups, onClose: nil)
                    .first(where: {
                        guard case .group(let group) = $0 else { return false }
                        let creatorInboxId = try await group.creatorInboxId()
                        let tag = try group.inviteTag
                        return (creatorInboxId == invite.payload.creatorInboxID &&
                                tag == invite.payload.tag)
                    }) {
                    guard !Task.isCancelled else { return }

                    // Accept consent and store the conversation
                    try await conversation.updateConsentState(state: .allowed)
                    Logger.info("Joined conversation with id: \(conversation.id)")

                    let messageWriter = IncomingMessageWriter(databaseWriter: databaseWriter)
                    let conversationWriter = ConversationWriter(
                        identityStore: identityStore,
                        databaseWriter: databaseWriter,
                        messageWriter: messageWriter
                    )
                    let dbConversation = try await conversationWriter.store(conversation: conversation)

                    // Create invite
                    let inviteWriter = InviteWriter(identityStore: identityStore, databaseWriter: databaseWriter)
                    _ = try await inviteWriter.generate(for: dbConversation, expiresAt: nil)

                    // Subscribe to push notifications
                    let topic = conversation.id.xmtpGroupTopicFormat
                    do {
                        try await apiClient.subscribeToTopics(installationId: client.installationId, topics: [topic])
                        Logger.info("Subscribed to push topic after join: \(topic)")
                    } catch {
                        Logger.error("Failed subscribing to topic after join \(topic): \(error)")
                    }

                    // Transition directly to ready state
                    await self.emitStateChange(.ready(ConversationReadyResult(
                        conversationId: conversation.id,
                        origin: .joined
                    )))

                    // Clear unused inbox from keychain now that conversation is successfully joined
                    await UnusedInboxCache.shared
                        .clearUnusedInbox(
                            with: client.inboxId,
                            databaseWriter: databaseWriter,
                            databaseReader: databaseReader,
                            environment: environment
                        )

                    // Clean up previous conversation if it exists and is different
                    await self.cleanUpPreviousConversationIfNeeded(
                        previousResult: previousReadyResult,
                        newConversationId: conversation.id,
                        client: client,
                        apiClient: apiClient
                    )
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

            try await inboxStateManager.delete()
        }

        emitStateChange(.uninitialized)
    }

    private func cleanUpPreviousConversationIfNeeded(
        previousResult: ConversationReadyResult?,
        newConversationId: String,
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

        let topic = conversationId.xmtpGroupTopicFormat
        do {
            try await apiClient.unsubscribeFromTopics(installationId: client.installationId, topics: [topic])
            Logger.info("Unsubscribed from push topic: \(topic)")
        } catch {
            Logger.error("Failed unsubscribing from topic \(topic): \(error)")
            // Continue with cleanup even if unsubscribe fails
        }

        // Clean up database records
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
}

// MARK: - Errors

public enum ConversationStateMachineError: Error {
    case failedFindingConversation
    case failedVerifyingSignature
    case stateMachineError(Error)
    case inviteExpired
    case invalidInviteCodeFormat(String)
    case timedOut
}
