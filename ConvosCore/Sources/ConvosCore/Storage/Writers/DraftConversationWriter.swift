import Combine
import Foundation
import GRDB

public protocol DraftConversationWriterProtocol: OutgoingMessageWriterProtocol {
    var draftConversationId: String { get }
    var conversationId: String { get }
    var conversationIdPublisher: AnyPublisher<String, Never> { get }
    var conversationMetadataWriter: any ConversationMetadataWriterProtocol { get }

    func createConversationWhenInboxReady()
    func requestToJoinWhenInboxReady(inviteCode: String)
}

class DraftConversationWriter: DraftConversationWriterProtocol {
    enum DraftConversationWriterError: Error {
        case missingClientProvider,
             missingConversationMembers,
             failedFindingConversation,
             missingCurrentUser,
             missingProfileForRemoving,
             modifyingMembersOnExistingConversation,
             inboxReadyTimeout
    }

    private enum DraftConversationWriterState: Equatable {
        case draft(id: String)
        case existing(id: String)
        case created(id: String)

        var id: String {
            switch self {
            case .draft(let id), .existing(let id), .created(let id):
                return id
            }
        }
    }

    private let databaseReader: any DatabaseReader
    private let databaseWriter: any DatabaseWriter
    private let inboxReadyValue: PublisherValue<InboxReadyResult>
    private let isSendingValue: CurrentValueSubject<Bool, Never> = .init(false)
    private let sentMessageSubject: PassthroughSubject<String, Never> = .init()
    private let inviteWriter: any InviteWriterProtocol
    let conversationMetadataWriter: any ConversationMetadataWriterProtocol

    var isSendingPublisher: AnyPublisher<Bool, Never> {
        isSendingValue.eraseToAnyPublisher()
    }

    var sentMessage: AnyPublisher<String, Never> {
        sentMessageSubject.eraseToAnyPublisher()
    }

    private var state: DraftConversationWriterState {
        didSet {
            Logger.info("State changed from \(oldValue) to \(state)")
            conversationIdSubject.send(state.id)
        }
    }

    let draftConversationId: String
    private let conversationIdSubject: CurrentValueSubject<String, Never>
    var conversationId: String {
        conversationIdSubject.value
    }
    var conversationIdPublisher: AnyPublisher<String, Never> {
        conversationIdSubject.eraseToAnyPublisher()
    }
    private var clientPublisherCancellable: AnyCancellable?
    private var createConversationTask: Task<Void, Never>?
    private var joinConversationTask: Task<Void, Never>?
    private var publishConversationTask: Task<Void, Never>?
    private var streamConversationsTask: Task<Void, Never>?

    init(inboxReadyValue: PublisherValue<InboxReadyResult>,
         databaseReader: any DatabaseReader,
         databaseWriter: any DatabaseWriter,
         draftConversationId: String) {
        self.inboxReadyValue = inboxReadyValue
        self.databaseReader = databaseReader
        self.databaseWriter = databaseWriter
        self.state = .draft(id: draftConversationId)
        self.conversationIdSubject = .init(draftConversationId)
        self.draftConversationId = draftConversationId
        self.inviteWriter = InviteWriter(databaseWriter: databaseWriter)
        self.conversationMetadataWriter = ConversationMetadataWriter(
            inboxReadyValue: inboxReadyValue,
            databaseWriter: databaseWriter
        )
    }

    deinit {
        cleanup()
    }

    func cleanup() {
        clientPublisherCancellable?.cancel()
        createConversationTask?.cancel()
        joinConversationTask?.cancel()
        publishConversationTask?.cancel()
        streamConversationsTask?.cancel()
        inboxReadyValue.dispose()
    }

    func createConversationWhenInboxReady() {
        createConversationTask?.cancel()
        clientPublisherCancellable?.cancel()
        clientPublisherCancellable = inboxReadyValue
            .publisher
            .compactMap { $0 }
            .first()
            .eraseToAnyPublisher()
            .sink { [weak self] inboxReady in
                guard let self else { return }
                self.createConversationTask = Task { [weak self] in
                    guard let self else { return }
                    do {
                        try await self.createExternalConversation(
                            client: inboxReady.client,
                            apiClient: inboxReady.apiClient
                        )
                    } catch {
                        Logger.error("Error creating external conversation: \(error.localizedDescription)")
                    }
                }
            }
    }

    func requestToJoinWhenInboxReady(inviteCode: String) {
        joinConversationTask?.cancel()
        clientPublisherCancellable?.cancel()
        clientPublisherCancellable = inboxReadyValue
            .publisher
            .compactMap { $0 }
            .first()
            .eraseToAnyPublisher()
            .sink { [weak self] inboxReady in
                guard let self else { return }
                Logger.info("Inbox ready, joining conversation...")
                self.joinConversationTask = Task { [weak self] in
                    guard let self else { return }
                    do {
                        try await self.requestToJoin(
                            inviteCode: inviteCode,
                            client: inboxReady.client,
                            apiClient: inboxReady.apiClient
                        )
                    } catch {
                        Logger.error("Error requesting to join conversation: \(error.localizedDescription)")
                    }
                }
            }
    }

    private func requestToJoin(
        inviteCode: String,
        client: AnyClientProvider,
        apiClient: any ConvosAPIClientProtocol
    ) async throws {
        // Call API to request to join
        _ = try await apiClient.requestToJoin(inviteCode)

        // Then wait for conversation to appear and finalize
        streamConversationsTask = Task { [weak self] in
            do {
                Logger.info("Started streaming conversations for inboxId: \(client.inboxId)")
                for try await conversation in await client.conversationsProvider.stream(
                    type: .groups,
                    onClose: {
                        Logger.warning("Closing conversations stream for inboxId: \(client.inboxId)...")
                    }
                ) {
                    guard let self else { return }

                    // Accept consent and store on first matching conversation for this invite
                    try await conversation.updateConsentState(state: .allowed)
                    Logger.info("Joined conversation with id: \(conversation.id)")

                    let messageWriter = IncomingMessageWriter(databaseWriter: databaseWriter)
                    let conversationWriter = ConversationWriter(databaseWriter: databaseWriter,
                                                                messageWriter: messageWriter)
                    Logger.info("Current state conversation id: \(conversationId)")
                    let dbConversation = try await conversationWriter.store(conversation: conversation,
                                                                            clientConversationId: conversationId)
                    Logger.info("Created conversation in database: \(dbConversation)")
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
                    try await inviteWriter.store(
                        invite: inviteResponse,
                        inboxId: client.inboxId
                    )
                    self.state = .existing(id: conversation.id)

                    // Subscribe to push topic upon join
                    let topic = conversation.id.xmtpGroupTopicFormat
                    do {
                        try await apiClient.subscribeToTopics(installationId: client.installationId, topics: [topic])
                        Logger.info("Subscribed to push topic after join: \(topic)")
                    } catch {
                        Logger.error("Failed subscribing to topic after join \(topic): \(error)")
                    }
                    streamConversationsTask?.cancel()
                    break
                }
            } catch {
                Logger.error("Error streaming conversations: \(error)")
            }
        }
    }

    private func createDraftConversation(conversationId: String, inboxId: String) throws {
        let conversation = DBConversation(
            id: draftConversationId,
            inboxId: inboxId,
            clientConversationId: draftConversationId,
            creatorId: inboxId,
            kind: .group,
            consent: .allowed,
            createdAt: Date(),
            name: nil,
            description: nil,
            imageURLString: nil
        )
        try databaseWriter.write { db in
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
            Logger.info("Saved draft conversation")
        }
    }

    private func createExternalConversation(
        client: AnyClientProvider,
        apiClient: any ConvosAPIClientProtocol
    ) async throws {
        guard case .draft = state else { return }

        let optimisticConversation = try await client.prepareConversation()
        let externalConversationId = optimisticConversation.id
        state = .created(id: externalConversationId)
        try await optimisticConversation.publish()

        guard let createdConversation = try await client.conversation(
            with: externalConversationId
        ) else {
            throw DraftConversationWriterError.failedFindingConversation
        }

        guard case .group(let group) = createdConversation else {
            Logger.error("Created conversation was not a group, returning...")
            return
        }

        try await group.updateAddMemberPermission(newPermissionOption: .allow)

        let messageWriter = IncomingMessageWriter(databaseWriter: databaseWriter)
        let conversationWriter = ConversationWriter(databaseWriter: databaseWriter,
                                                    messageWriter: messageWriter)
        _ = try await conversationWriter.store(conversation: createdConversation,
                                               clientConversationId: conversationId)

        // Subscribe to push topic for this conversation
        let topic = externalConversationId.xmtpGroupTopicFormat
        do {
            try await apiClient.subscribeToTopics(installationId: client.installationId, topics: [topic])
            Logger.info("Subscribed to push topic: \(topic)")
        } catch {
            Logger.error("Failed subscribing to topic \(topic): \(error)")
        }

        let response = try await apiClient.createInvite(
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
        let invite = try await inviteWriter.store(invite: response, inboxId: client.inboxId)
        Logger.info("Created invite for conversation \(externalConversationId): \(invite)")
    }

    func send(text: String) async throws {
        guard let client = inboxReadyValue.value?.client else {
            throw InboxStateError.inboxNotReady
        }

        isSendingValue.send(true)

        defer {
            isSendingValue.send(false)
        }

        switch state {
        case .existing(let id), .created(let id):
            // send the message
            let messageWriter = OutgoingMessageWriter(
                client: client,
                clientPublisher: inboxReadyValue.publisher.compactMap { $0?.client }.eraseToAnyPublisher(),
                databaseWriter: databaseWriter,
                conversationId: id
            )

            try await messageWriter.send(text: text)
            sentMessageSubject.send(text)
        case .draft(let id):
            // save a temporary message to the draft conversation
            try await databaseWriter.write { [weak self] db in
                guard let self else { return }

                let creatorProfile = MemberProfile(
                    inboxId: client.inboxId,
                    name: nil,
                    avatar: nil,
                )
                try creatorProfile.insert(db, onConflict: .ignore)

                // add the current user as a member
                let conversationMember = DBConversationMember(
                    conversationId: conversationId,
                    inboxId: client.inboxId,
                    role: .superAdmin,
                    consent: .allowed,
                    createdAt: Date()
                )
                try conversationMember.save(db)

                let clientMessageId = UUID().uuidString
                let localMessage = DBMessage(
                    id: clientMessageId,
                    clientMessageId: clientMessageId,
                    conversationId: conversationId,
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
                Logger.info("Saved local message with local id: \(localMessage.clientMessageId)")
            }

            let draftConversation = try await databaseReader.read { [weak self] db -> DBConversation? in
                guard let self else { return nil }
                return try DBConversation.fetchOne(db, key: conversationId)
            }?.with(id: id)
            try await databaseWriter.write { db in
                try draftConversation?.save(db)
            }

            sentMessageSubject.send(text)
        }
    }
}
