import Combine
import Foundation
import GRDB
import XMTPiOS

public struct ConversationReadyResult {
    public let conversationId: String
    public let externalConversationId: String
    public let invite: Invite?
}

public actor ConversationStateMachine {
    enum Action {
        case create
        case join(inviteCode: String)
        case sendMessage(text: String)
        case delete
        case stop
    }

    public enum State: Equatable {
        case uninitialized
        case creating
        case joining(inviteCode: String)
        case ready(ConversationReadyResult)
        case deleting
        case error(String)

        public static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.uninitialized, .uninitialized),
                 (.creating, .creating),
                 (.deleting, .deleting):
                return true
            case let (.joining(lhsCode), .joining(rhsCode)):
                return lhsCode == rhsCode
            case let (.ready(lhsResult), .ready(rhsResult)):
                return lhsResult.conversationId == rhsResult.conversationId
            case let (.error(lhsError), .error(rhsError)):
                return lhsError == rhsError
            default:
                return false
            }
        }
    }

    // MARK: - Properties

    private let draftConversationId: String
    private let inboxStateManager: InboxStateManager
    private let databaseReader: any DatabaseReader
    private let databaseWriter: any DatabaseWriter
    private let inviteWriter: any InviteWriterProtocol

    private var currentTask: Task<Void, Never>?
    private var streamConversationsTask: Task<Void, Never>?
    private var actionQueue: [Action] = []
    private var isProcessing: Bool = false

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
        continuation.yield(_state)
        continuation.onTermination = { [weak self] _ in
            Task {
                await self?.removeStateContinuation(continuation)
            }
        }
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
        draftConversationId: String,
        inboxStateManager: InboxStateManager,
        databaseReader: any DatabaseReader,
        databaseWriter: any DatabaseWriter,
        inviteWriter: any InviteWriterProtocol
    ) {
        self.draftConversationId = draftConversationId
        self.inboxStateManager = inboxStateManager
        self.databaseReader = databaseReader
        self.databaseWriter = databaseWriter
        self.inviteWriter = inviteWriter
    }

    deinit {
        streamConversationsTask?.cancel()
        currentTask?.cancel()
    }

    // MARK: - Public Actions

    func create() {
        enqueueAction(.create)
    }

    func join(inviteCode: String) {
        enqueueAction(.join(inviteCode: inviteCode))
    }

    func sendMessage(text: String) {
        enqueueAction(.sendMessage(text: text))
    }

    func delete() {
        enqueueAction(.delete)
    }

    func stop() {
        enqueueAction(.stop)
    }

    func waitForReadyState() async throws -> ConversationReadyResult {
        for await state in stateSequence {
            switch state {
            case .ready(let result):
                return result
            case .error(let message):
                throw ConversationStateMachineError.stateMachineError(message)
            default:
                continue
            }
        }
        throw ConversationStateMachineError.unexpectedTermination
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

        currentTask = Task {
            await processAction(action)
            isProcessing = false
            processNextAction()
        }
    }

    private func processAction(_ action: Action) async {
        do {
            switch (_state, action) {
            case (.uninitialized, .create):
                try await handleCreate()
            case (.uninitialized, let .join(inviteCode)):
                try await handleJoin(inviteCode: inviteCode)
            case (_, let .sendMessage(text)):
                try await handleSendMessage(text: text)
            case (.ready, .delete), (.error, .delete):
                try await handleDelete()
            case (_, .stop):
                handleStop()
            default:
                Logger.warning("Invalid state transition: \(_state) -> \(action)")
            }
        } catch {
            Logger.error("Failed state transition \(_state) -> \(action): \(error.localizedDescription)")
            emitStateChange(.error(error.localizedDescription))
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
        _ = try await conversationWriter.store(conversation: createdConversation, clientConversationId: draftConversationId)

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
            conversationId: draftConversationId,
            externalConversationId: externalConversationId,
            invite: invite
        )))
    }

    private func handleJoin(inviteCode: String) async throws {
        emitStateChange(.joining(inviteCode: inviteCode))

        let inboxReady = try await inboxStateManager.waitForInboxReadyResult()
        Logger.info("Inbox ready, requesting to join conversation...")

        let apiClient = inboxReady.apiClient
        let client = inboxReady.client

        // Request to join
        let response = try await apiClient.requestToJoin(inviteCode)
        let conversationId = response.invite.groupId

        // Stream conversations to wait for the joined conversation
        streamConversationsTask = Task { [weak self] in
            do {
                Logger.info("Started streaming conversations for inboxId: \(client.inboxId), looking for convo: \(conversationId)...")
                for try await conversation in await client.conversationsProvider.stream(
                    type: .groups,
                    onClose: {
                        Logger.warning("Closing conversations stream...")
                    }
                ) where conversation.id == conversationId {
                    guard let self else { return }
                    guard !Task.isCancelled else { return }

                    // Accept consent and store the conversation
                    try await conversation.updateConsentState(state: .allowed)
                    Logger.info("Joined conversation with id: \(conversation.id)")

                    let messageWriter = IncomingMessageWriter(databaseWriter: databaseWriter)
                    let conversationWriter = ConversationWriter(databaseWriter: databaseWriter, messageWriter: messageWriter)
                    _ = try await conversationWriter.store(conversation: conversation, clientConversationId: draftConversationId)

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
                        conversationId: draftConversationId,
                        externalConversationId: conversation.id,
                        invite: invite
                    )))

                    await streamConversationsTask?.cancel()
                    break
                }
            } catch {
                Logger.error("Error streaming conversations: \(error)")
                await self?.emitStateChange(.error(error.localizedDescription))
            }
        }
    }

    private func handleSendMessage(text: String) async throws {
        switch _state {
        case .ready(let result):
            // For ready conversations, use the regular message writer
            let messageWriter = OutgoingMessageWriter(
                inboxStateManager: inboxStateManager,
                databaseWriter: databaseWriter,
                conversationId: result.externalConversationId
            )
            try await messageWriter.send(text: text)

        case .uninitialized, .creating, .joining:
            // For draft conversations, save a local message
            let inboxReady = try await inboxStateManager.waitForInboxReadyResult()
            let client = inboxReady.client

            // First ensure the draft conversation exists in the database
            try await ensureDraftConversationExists(inboxId: client.inboxId)

            // Save the message locally
            try await databaseWriter.write { db in
                let clientMessageId = UUID().uuidString
                let localMessage = DBMessage(
                    id: clientMessageId,
                    clientMessageId: clientMessageId,
                    conversationId: self.draftConversationId,
                    senderId: client.inboxId,
                    date: Date(),
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

        case .error(let message):
            throw ConversationStateMachineError.stateMachineError(message)
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

    private func handleDelete() async throws {
        emitStateChange(.deleting)

        // Cancel any ongoing tasks
        streamConversationsTask?.cancel()

        // TODO: Clean up conversation data if needed

        emitStateChange(.uninitialized)
    }

    private func handleStop() {
        streamConversationsTask?.cancel()
        emitStateChange(.uninitialized)
    }
}

// MARK: - Errors

enum ConversationStateMachineError: Error {
    case failedFindingConversation
    case notReady
    case stateMachineError(String)
    case unexpectedTermination
}
