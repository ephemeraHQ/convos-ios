import Combine
import Foundation
import GRDB

protocol DraftConversationWriterProtocol: OutgoingMessageWriterProtocol {
    var draftConversationId: String { get }
    var conversationId: String { get }
    var conversationIdPublisher: AnyPublisher<String, Never> { get }
}

class DraftConversationWriter: DraftConversationWriterProtocol {
    enum DraftConversationWriterError: Error {
        case missingClientProvider,
             missingConversationMembers,
             failedFindingConversation,
             missingCurrentUser,
             missingProfileForRemoving,
             modifyingMembersOnExistingConversation
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

    var isSendingPublisher: AnyPublisher<Bool, Never> {
        isSendingValue.eraseToAnyPublisher()
    }

    var sentMessage: AnyPublisher<String, Never> {
        sentMessageSubject.eraseToAnyPublisher()
    }

    private var state: DraftConversationWriterState {
        didSet {
            Logger.info("DraftConversationWriter state changed from \(oldValue) to \(state)")
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

        clientPublisherCancellable = inboxReadyValue
            .publisher
            .compactMap { $0 }
            .first()
            .eraseToAnyPublisher()
            .sink { [weak self] inboxReady in
                guard let self else { return }
                Task {
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

    private func addDraftConversation(inboxId: String) async throws {
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

        try await databaseWriter.write { [inboxId] db in
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
                inboxId: inboxId,
                role: .superAdmin,
                consent: .allowed,
                createdAt: Date()
            )
            try conversationMember.save(db)
            Logger.info("Saved conversation member and updated conversation to database")
        }

        Logger.info("No existing conversation found, staying in draft state")
        state = .draft(id: draftConversationId)
    }

    private func createExternalConversation(
        client: AnyClientProvider,
        apiClient: any ConvosAPIClientProtocol
    ) async throws {
        let externalConversationId = try await client.newConversation(
            with: [ client.inboxId ],
            name: "",
            description: "",
            imageUrl: ""
        )
        state = .created(id: externalConversationId)

        guard let createdConversation = try await client.conversation(
            with: externalConversationId
        ) else {
            throw DraftConversationWriterError.failedFindingConversation
        }

        let draftConversation = try await databaseReader.read { [weak self] db -> DBConversation? in
            guard let self else { return nil }
            return try DBConversation.fetchOne(db, key: conversationId)
        }?.with(id: externalConversationId)
        try await databaseWriter.write { db in
            try draftConversation?.save(db)
        }

        let messageWriter = IncomingMessageWriter(databaseWriter: databaseWriter)
        let conversationWriter = ConversationWriter(databaseWriter: databaseWriter,
                                                    messageWriter: messageWriter)
        _ = try await conversationWriter.store(conversation: createdConversation,
                                               clientConversationId: conversationId)

        let response = try await apiClient.createInvite(
            .init(
                groupId: externalConversationId,
                name: nil,
                description: nil,
                imageUrl: nil,
                maxUses: nil,
                expiresAt: nil
            )
        )
        let invite = try await inviteWriter.store(invite: response)
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
                    name: "",
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
