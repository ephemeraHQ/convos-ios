import Combine
import Foundation
import GRDB
import XMTPiOS

public struct ConversationReadyResult {
    let inboxId: String
    public let conversationId: String
    public let invite: Invite
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
        case validated(invite: ConvosAPI.InviteDetailsWithGroupResponse, inboxReady: InboxReadyResult)
        case joining(invite: ConvosAPI.InviteDetailsWithGroupResponse)
        case ready(ConversationReadyResult)
        case deleting
        case error(Error)

        public static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.uninitialized, .uninitialized),
                 (.creating, .creating),
                 (.deleting, .deleting):
                return true
            case let (.joining(lhsInvite), .joining(rhsInvite)):
                return lhsInvite.id == rhsInvite.id
            case let (.validating(lhsCode), .validating(rhsCode)):
                return lhsCode == rhsCode
            case let (.validated(lhsInvite, lhsInbox), .validated(rhsInvite, rhsInbox)):
                return lhsInvite.id == rhsInvite.id && lhsInbox.client.inboxId == rhsInbox.client.inboxId
            case let (.ready(lhsResult), .ready(rhsResult)):
                return (lhsResult.conversationId == rhsResult.conversationId &&
                        lhsResult.invite.id == rhsResult.invite.id)
            default:
                return false
            }
        }
    }

    // MARK: - Properties

    private let inboxStateManager: any InboxStateManagerProtocol
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
        inboxStateManager: any InboxStateManagerProtocol,
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

            case (.uninitialized, let .validate(inviteCode)):
                try await handleValidate(inviteCode: inviteCode)
            case (.ready, let .validate(inviteCode)):
                try await handleValidateFromReadyState(inviteCode: inviteCode)

            case (let .validated(invite, inboxReady), .join):
                try await handleJoin(invite: invite, inboxReady: inboxReady)

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
            inboxId: client.inboxId,
            conversationId: externalConversationId,
            invite: invite
        )))
    }

    private func handleValidateFromReadyState(inviteCode: String) async throws {
        let previousResult: ConversationReadyResult? = switch _state {
        case .ready(let result):
            result
        default:
            nil
        }

        // Try to join the new conversation
        try await handleValidate(inviteCode: inviteCode)

        // If the join succeeded, clean up the previous conversation
        if let previousResult {
            Logger.info("Join succeeded, cleaning up previous conversation: \(previousResult.conversationId)")

            // Get the inbox state to access the API client for unsubscribing
            let inboxReady = try await inboxStateManager.waitForInboxReadyResult()
            await scheduleCleanupOnNextReady(
                previousConversationId: previousResult.conversationId,
                previousInboxId: previousResult.inboxId,
                client: inboxReady.client,
                apiClient: inboxReady.apiClient,
            )
        }
    }

    private func handleValidate(inviteCode: String) async throws {
        emitStateChange(.validating(inviteCode: inviteCode))

        Logger.info("Validating invite code '\(inviteCode)'")

        let code: String
        let trimmedInviteCode = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines)
        // Try to extract invite code from URL first
        if let url = URL(string: trimmedInviteCode), let extractedCode = url.convosInviteCode {
            code = extractedCode
        } else if trimmedInviteCode.count >= 8 {
            code = trimmedInviteCode
        } else {
            throw ConversationStateMachineError.invalidInviteCodeFormat(inviteCode)
        }

        Logger.info("Extracted invite code '\(code)', checking if we're already a member...")

        let draftConversationId = self.draftConversationId
        let resultByInviteCode: ConversationReadyResult? = try await databaseReader.read { db in
            guard let existingInvite = try DBInvite.fetchOne(db, key: code) else {
                return nil
            }
            guard let existingConversation = try DBConversation.fetchOne(db, key: existingInvite.conversationId) else {
                return nil
            }
            return .init(
                inboxId: existingConversation.inboxId,
                conversationId: draftConversationId,
                externalConversationId: existingConversation.id,
                invite: existingInvite.hydrateInvite()
            )
        }

        if let resultByInviteCode {
            Logger.info("Found existing convo by invite code, returning...")
            emitStateChange(.ready(resultByInviteCode))
            return
        }

        Logger.info("Waiting for inbox ready result...")
        let inboxReady = try await inboxStateManager.waitForInboxReadyResult()
        Logger.info("Inbox ready, validating invite code on backend...")

        let apiClient = inboxReady.apiClient
        let inviteDetails: ConvosAPI.InviteDetailsWithGroupResponse
        do {
            inviteDetails = try await apiClient.inviteDetailsWithGroup(code)
        } catch {
            Logger.error("Error fetching invite details: \(error.localizedDescription)")
            throw ConversationStateMachineError.inviteExpired
        }

        let conversationId = inviteDetails.groupId
        let resultByConversationId: ConversationReadyResult? = try await databaseReader.read { db in
            guard let existingConversation = try DBConversation.fetchOne(db, key: conversationId) else {
                return nil
            }
            guard let existingInvite = try DBInvite
                .filter(DBInvite.Columns.conversationId == conversationId)
                .fetchOne(db) else {
                return nil
            }
            return .init(
                inboxId: existingConversation.inboxId,
                conversationId: draftConversationId,
                externalConversationId: existingConversation.id,
                invite: existingInvite.hydrateInvite()
            )
        }

        if let resultByConversationId {
            Logger.info("Found existing convo by id, returning...")
            emitStateChange(.ready(resultByConversationId))
            return
        }

        Logger.info("Existing conversation not found. Proceeding to join...")
        emitStateChange(.validated(invite: inviteDetails, inboxReady: inboxReady))
        enqueueAction(.join)
    }

    private func handleJoin(invite: ConvosAPI.InviteDetailsWithGroupResponse, inboxReady: InboxReadyResult) async throws {
        emitStateChange(.joining(invite: invite))

        Logger.info("Requesting to join conversation...")

        let apiClient = inboxReady.apiClient
        let client = inboxReady.client

        // Request to join
        let response = try await apiClient.requestToJoin(invite.id)
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
<<<<<<< HEAD
                        conversationId: conversation.id,
=======
                        inboxId: client.inboxId,
                        conversationId: draftConversationId,
                        externalConversationId: conversation.id,
>>>>>>> b9130a6 (Join Flow Improvements (#150))
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

<<<<<<< HEAD
=======
    private func handleSendMessage(text: String) async throws {
        switch _state {
        case .ready(let result):
            // For ready conversations, use the regular message writer
            Logger.info("Sending message for ready result: \(result)")
            let messageWriter = OutgoingMessageWriter(
                inboxStateManager: inboxStateManager,
                databaseWriter: databaseWriter,
                conversationId: result.externalConversationId
            )
            try await messageWriter.send(text: text)

        case .uninitialized, .creating, .validating, .validated, .joining:
            // For draft conversations, save a local message
            let inboxReady = try await inboxStateManager.waitForInboxReadyResult()
            let client = inboxReady.client

            // First ensure the draft conversation exists in the database
            try await ensureDraftConversationExists(inboxId: client.inboxId)

            // Save the message locally
            let date = Date()
            try await databaseWriter.write { db in
                let clientMessageId = UUID().uuidString
                let localMessage = DBMessage(
                    id: clientMessageId,
                    clientMessageId: clientMessageId,
                    conversationId: self.draftConversationId,
                    senderId: client.inboxId,
                    dateNs: date.nanosecondsSince1970,
                    date: date,
                    status: .unpublished,
                    messageType: .original,
                    contentType: .text,
                    text: text,
                    emoji: nil,
                    sourceMessageId: nil,
                    attachmentUrls: [],
                    update: nil
                )

                try localMessage.save(db)
                Logger.info("Saved local message with id: \(localMessage.clientMessageId)")
            }

        case .deleting:
            Logger.warning("Cannot send message while conversation is being deleted")

        case .error(let error):
            throw ConversationStateMachineError.stateMachineError(error)
        }
    }

    private func ensureDraftConversationExists(inboxId: String) async throws {
        let conversationExists = try await databaseReader.read { db in
            try DBConversation.fetchOne(db, key: self.draftConversationId) != nil
        }

        guard !conversationExists else { return }

        // Create the draft conversation and necessary records
        try await databaseWriter.write { db in
            let conversation = DBConversation(
                id: self.draftConversationId,
                inboxId: inboxId,
                clientConversationId: self.draftConversationId,
                creatorId: inboxId,
                kind: .group,
                consent: .allowed,
                createdAt: Date(),
                name: nil,
                description: nil,
                imageURLString: nil
            )

            let memberProfile = MemberProfile(inboxId: inboxId, name: nil, avatar: nil)
            let member = Member(inboxId: inboxId)

            try member.save(db)
            try memberProfile.save(db)
            try conversation.save(db)

            let localState = ConversationLocalState(
                conversationId: conversation.id,
                isPinned: false,
                isUnread: false,
                isUnreadUpdatedAt: Date(),
                isMuted: false
            )
            try localState.save(db)

            let conversationMember = DBConversationMember(
                conversationId: conversation.id,
                inboxId: memberProfile.inboxId,
                role: .superAdmin,
                consent: .allowed,
                createdAt: Date()
            )
            try conversationMember.save(db)

            Logger.info("Created draft conversation")
        }
    }

>>>>>>> b9130a6 (Join Flow Improvements (#150))
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

    // After the next .ready, if the conversation changed, clean up the previously created convo.
    private func scheduleCleanupOnNextReady(
        previousConversationId: String,
        previousInboxId: String,
        client: any XMTPClientProvider,
        apiClient: any ConvosAPIClientProtocol,
    ) async {
        for await state in self.stateSequence {
            switch state {
            case .ready(let newReady):
                guard previousInboxId == client.inboxId else {
                    Logger.info("inboxId changed, skipping scheduled cleanup...")
                    return
                }

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
    case inviteExpired
    case invalidInviteCodeFormat(String)
    case timedOut
}
