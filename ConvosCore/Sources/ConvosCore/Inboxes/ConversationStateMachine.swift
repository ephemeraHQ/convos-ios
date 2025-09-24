import Combine
import Foundation
import GRDB
import XMTPiOS

public struct ConversationReadyResult {
    public let conversationId: String
    public let invite: Invite
}

public actor ConversationStateMachine {
    enum Action {
        case create
        case join(inviteCode: String)
        case delete
        case stop
    }

    public enum State: Equatable {
        case uninitialized
        case creating
        case joining(inviteCode: String)
        case ready(ConversationReadyResult)
        case deleting
        case error(Error)

        public static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.uninitialized, .uninitialized),
                 (.creating, .creating),
                 (.deleting, .deleting):
                return true
            case let (.joining(lhsCode), .joining(rhsCode)):
                return lhsCode == rhsCode
            case let (.ready(lhsResult), .ready(rhsResult)):
                return (lhsResult.conversationId == rhsResult.conversationId &&
                        lhsResult.invite.id == rhsResult.invite.id)
            default:
                return false
            }
        }
    }

    // MARK: - Properties

    private let inboxStateManager: InboxStateManager
    private let databaseReader: any DatabaseReader
    private let databaseWriter: any DatabaseWriter
    private let inviteWriter: any InviteWriterProtocol

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
        inboxStateManager: InboxStateManager,
        databaseReader: any DatabaseReader,
        databaseWriter: any DatabaseWriter,
        inviteWriter: any InviteWriterProtocol
    ) {
        self.inboxStateManager = inboxStateManager
        self.databaseReader = databaseReader
        self.databaseWriter = databaseWriter
        self.inviteWriter = inviteWriter
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
        }

        // Start a single task that processes messages in order
        messageProcessingTask = Task.detached { [weak self] in
            for await message in stream {
                guard let self else { break }
                await self.processMessage(message)
            }
        }
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
        enqueueAction(.join(inviteCode: inviteCode))
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
            case (.uninitialized, let .join(inviteCode)):
                try await handleJoin(inviteCode: inviteCode)
            case (.ready, let .join(inviteCode)):
                try await handleJoinFromReadyState(inviteCode: inviteCode)
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

    private func findExistingConversationForInviteCode(_ inviteCode: String) async throws -> String? {
        let lookupUtility = ConversationLookupUtility(databaseReader: databaseReader)
        return try await lookupUtility.findExistingConversationForInviteCode(inviteCode)
    }

    private func handleCreate() async throws {
        emitStateChange(.creating)

        let inboxReady = try await inboxStateManager.waitForInboxReadyResult()
        Logger.info("Inbox ready, creating conversation...")

        let client = inboxReady.client
        let apiClient = inboxReady.apiClient

        // Create the optimistic conversation
        let optimisticConversation = try await client.prepareConversation()
        let externalConversationId = optimisticConversation.id

        // Publish the conversation
        try await optimisticConversation.publish()

        // Fetch the created conversation
        guard let createdConversation = try await client.conversation(with: externalConversationId) else {
            throw ConversationStateMachineError.failedFindingConversation
        }

        // Update permissions for group conversations
        if case .group(let group) = createdConversation {
            try await group.updateAddMemberPermission(newPermissionOption: .allow)
        }

        // Store the conversation
        let messageWriter = IncomingMessageWriter(databaseWriter: databaseWriter)
        let conversationWriter = ConversationWriter(databaseWriter: databaseWriter, messageWriter: messageWriter)
        _ = try await conversationWriter.store(conversation: createdConversation)

        // Subscribe to push notifications
        let topic = externalConversationId.xmtpGroupTopicFormat
        do {
            try await apiClient.subscribeToTopics(installationId: client.installationId, topics: [topic])
            Logger.info("Subscribed to push topic: \(topic)")
        } catch {
            Logger.error("Failed subscribing to topic \(topic): \(error)")
        }

        // Create invite
        let inviteResponse = try await apiClient.createInvite(
            .init(
                groupId: externalConversationId,
                name: nil,
                description: nil,
                imageUrl: nil,
                maxUses: nil,
                expiresAt: nil,
                autoApprove: true,
                notificationTargets: []
            )
        )
        let invite = try await inviteWriter.store(invite: inviteResponse, inboxId: client.inboxId)

        // Transition directly to ready state
        emitStateChange(.ready(ConversationReadyResult(
            conversationId: externalConversationId,
            invite: invite
        )))
    }

    private func handleJoinFromReadyState(inviteCode: String) async throws {
        let previousResult: ConversationReadyResult? = switch _state {
        case .ready(let result):
            result
        default:
            nil
        }

        // Try to join the new conversation
        try await handleJoin(inviteCode: inviteCode)

        // If the join succeeded, clean up the previous conversation
        if let previousResult {
            Logger.info("Join succeeded, cleaning up previous conversation: \(previousResult.conversationId)")

            // Get the inbox state to access the API client for unsubscribing
            let inboxReady = try await inboxStateManager.waitForInboxReadyResult()
            await scheduleCleanupOnNextReady(
                previousConversationId: previousResult.conversationId,
                client: inboxReady.client,
                apiClient: inboxReady.apiClient,
            )
        }
    }

    private func handleJoin(inviteCode: String) async throws {
        emitStateChange(.joining(inviteCode: inviteCode))

        let inboxReady = try await inboxStateManager.waitForInboxReadyResult()
        Logger.info("Inbox ready, requesting to join conversation...")

        let apiClient = inboxReady.apiClient
        let client = inboxReady.client

        // Check if we've already joined this conversation (invite code)
        if let existingConversationId = try await findExistingConversationForInviteCode(inviteCode) {
            Logger.info("Existing conversation found locally, cancelling join...")
            throw ConversationStateMachineError.alreadyRedeemedInviteForConversation(existingConversationId)
        }

        // Check if we're already a member of this group (groupId check)
        // Only do network check if we have existing conversations that might conflict
        let hasExistingConversations = try await databaseReader.read { db in
            try DBConversation.fetchCount(db) > 0
        }

        let inviteWithGroup = try await apiClient.inviteDetailsWithGroup(inviteCode)
        // @jarodl temporary backup to get around push notif delays
        // send the invite code to the inviter, observed by `InviteJoinRequestsManager`
        Task {
            do {
                let inviterInboxId = inviteWithGroup.inviterInboxId
                let dm = try await client.newConversation(with: inviterInboxId)
                _ = try await dm.prepare(text: inviteCode)
                try await dm.publish()
            } catch {
                Logger.error("Failed sending backup invite request over XMTP: \(error.localizedDescription)")
            }
        }

        if hasExistingConversations {
            let groupId = inviteWithGroup.groupId
            // Check local database for existing group membership
            if let existingConversation: DBConversation = try await databaseReader.read({ db in
                try DBConversation.fetchOne(db, key: groupId)
            }) {
                Logger.info("Already a member of group \(groupId), cancelling join...")
                throw ConversationStateMachineError.alreadyRedeemedInviteForConversation(existingConversation.id)
            }
        }

        // Request to join
        let response = try await apiClient.requestToJoin(inviteCode)
        let conversationId = response.invite.groupId

        // Stream conversations to wait for the joined conversation
        streamConversationsTask = Task { [weak self] in
            guard let self else { return }
            do {
                Logger.info("Started streaming conversations for inboxId: \(client.inboxId), looking for convo: \(conversationId)...")
                if let conversation = try await client.conversationsProvider
                    .stream(type: .groups, onClose: nil)
                    .first(where: { $0.id == conversationId }) {
                    guard !Task.isCancelled else { return }

                    // Accept consent and store the conversation
                    try await conversation.updateConsentState(state: .allowed)
                    Logger.info("Joined conversation with id: \(conversation.id)")

                    let messageWriter = IncomingMessageWriter(databaseWriter: databaseWriter)
                    let conversationWriter = ConversationWriter(databaseWriter: databaseWriter, messageWriter: messageWriter)
                    _ = try await conversationWriter.store(conversation: conversation)

                    // Store the invite we used so we don't join the same conversation again
                    let conversationCreatorInboxId = try await conversation.creatorInboxId
                    _ = try await inviteWriter.store(invite: response.invite, inboxId: conversationCreatorInboxId)

                    // Create invite for the joined conversation
                    let inviteResponse = try await apiClient.createInvite(
                        .init(
                            groupId: conversation.id,
                            name: nil,
                            description: nil,
                            imageUrl: nil,
                            maxUses: nil,
                            expiresAt: nil,
                            autoApprove: true,
                            notificationTargets: []
                        )
                    )
                    let invite = try await inviteWriter.store(invite: inviteResponse, inboxId: client.inboxId)

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
                        invite: invite
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
                apiClient: inboxReady.apiClient
            )
        }

        emitStateChange(.uninitialized)
    }

    // Runs once: after the next .ready for a different conversation, clean up the previous convo.
    private func scheduleCleanupOnNextReady(
        previousConversationId: String,
        client: any XMTPClientProvider,
        apiClient: any ConvosAPIClientProtocol,
    ) async {
        for await state in self.stateSequence {
            switch state {
            case .ready(let newReady):
                // Only clean up if we actually moved to a different external conversation
                if newReady.conversationId != previousConversationId {
                    do {
                        try await self.cleanUp(
                            conversationId: previousConversationId,
                            client: client,
                            apiClient: apiClient
                        )
                    } catch {
                        Logger.error("Deferred cleanup of previous conversation failed: \(error)")
                    }
                    return
                }
            case .error:
                return
            default:
                continue
            }
        }
    }

    private func cleanUp(
        conversationId: String,
        client: any XMTPClientProvider,
        apiClient: any ConvosAPIClientProtocol,
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
                .filter(Column("conversationId") == conversationId)
                .deleteAll(db)

            try DBInvite
                .filter(DBInvite.Columns.conversationId == conversationId)
                .deleteAll(db)

            try DBConversation
                .filter(DBConversation.Columns.id == conversationId)
                .deleteAll(db)

            Logger.info("Cleaned up conversation data for conversationId: \(conversationId)")
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
    case stateMachineError(Error)
    case alreadyRedeemedInviteForConversation(String)
    case timedOut
}
