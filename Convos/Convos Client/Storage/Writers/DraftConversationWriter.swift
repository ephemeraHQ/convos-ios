import Combine
import Foundation
import GRDB

protocol DraftConversationWriterProtocol: OutgoingMessageWriterProtocol {
    var draftConversationId: String { get }
    var conversationId: String { get }
    var conversationIdPublisher: AnyPublisher<String, Never> { get }

    func add(profile: MemberProfile) async throws
    func remove(profile: MemberProfile) async throws
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

        var canEditMembers: Bool {
            switch self {
            case .draft, .existing:
                return true
            case .created:
                return false
            }
        }
    }

    private let databaseReader: any DatabaseReader
    private let databaseWriter: any DatabaseWriter
    private let clientPublisher: AnyClientProviderPublisher
    private let clientValue: PublisherValue<AnyClientProvider>
    private let isSendingValue: CurrentValueSubject<Bool, Never> = .init(false)
    private let sentMessageSubject: PassthroughSubject<String, Never> = .init()

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

    init(client: AnyClientProvider?,
         clientPublisher: AnyClientProviderPublisher,
         databaseReader: any DatabaseReader,
         databaseWriter: any DatabaseWriter,
         draftConversationId: String) {
        self.clientPublisher = clientPublisher
        self.clientValue = .init(initial: client, upstream: clientPublisher)
        self.databaseReader = databaseReader
        self.databaseWriter = databaseWriter
        self.state = .draft(id: draftConversationId)
        self.conversationIdSubject = .init(draftConversationId)
        self.draftConversationId = draftConversationId
        removeOldDraftConversations()
    }

    private func removeOldDraftConversations() {
        Task {
            try await databaseWriter.write { [weak self] db in
                guard let self else { return }
                try DBConversation
                    .filter(Column("id").like("draft-%"))
                    .filter(Column("clientConversationId") != draftConversationId)
                    .deleteAll(db)
            }
        }
    }

    private func findMatchingConversation() async throws -> DBConversation? {
        guard let client = clientValue.value else {
            throw InboxStateError.inboxNotReady
        }

        return try await databaseReader.read { [weak self] db -> DBConversation? in
            guard let self else { return nil }
            let conversation = try DBConversation
                .filter(Column("clientConversationId") == draftConversationId)
                .fetchOne(db)

            var memberInboxIds = try conversation?.request(for: DBConversation.memberProfiles)
                .fetchAll(db)
                .map { $0.inboxId } ?? []
            memberInboxIds.append(client.inboxId)
            guard let conversation = try DBConversation.findConversationWith(
                members: memberInboxIds,
                inboxId: client.inboxId,
                db: db
            ) else {
                return nil
            }
            return conversation
        }
    }

    func add(profile: MemberProfile) async throws {
        Logger.info("Adding profile \(profile.inboxId) to draft conversation")
        guard let client = clientValue.value else {
            throw InboxStateError.inboxNotReady
        }

        guard state.canEditMembers else {
            throw DraftConversationWriterError.modifyingMembersOnExistingConversation
        }

        let inboxId = client.inboxId
        let conversation: DBConversation? = try await databaseReader.read { [draftConversationId, inboxId] db in
            if let existingDraft = try DBConversation
                .filter(Column("clientConversationId") == draftConversationId)
                .fetchOne(db) {
                Logger.info("Found existing draft conversation: \(existingDraft.id)")
                return existingDraft
            } else {
                Logger.info("Creating new draft conversation: \(draftConversationId)")
                return DBConversation(
                    id: draftConversationId,
                    inboxId: inboxId,
                    clientConversationId: draftConversationId,
                    creatorId: inboxId,
                    kind: .dm,
                    consent: .allowed,
                    createdAt: Date(),
                    name: nil,
                    description: nil,
                    imageURLString: nil
                )
            }
        }

        guard let conversation else {
            throw DraftConversationWriterError.failedFindingConversation
        }

        let membersCount: Int = try await databaseReader.read { db in
            try conversation.request(for: DBConversation.memberProfiles).fetchCount(db)
        }
        let updatedConversation = conversation.with(kind: (membersCount + 1) == 1 ? .dm : .group)
        Logger.info("Updated conversation kind to: \(updatedConversation.kind) (members: \(membersCount + 1))")

        try await databaseWriter.write { db in
            let member = Member(inboxId: profile.inboxId)
            try member.save(db)
            try profile.save(db)
            try updatedConversation.save(db)
            let localState = ConversationLocalState(
                conversationId: updatedConversation.id,
                isPinned: false,
                isUnread: false,
                isUnreadUpdatedAt: Date(),
                isMuted: false
            )
            try localState.save(db)
            let conversationMember = DBConversationMember(
                conversationId: updatedConversation.id,
                memberId: profile.inboxId,
                role: .member,
                consent: .allowed,
                createdAt: Date()
            )
            try conversationMember.save(db)
            Logger.info("Saved conversation member and updated conversation to database")
        }

        if let existingConversation = try await findMatchingConversation() {
            Logger.info("Found existing conversation, changing state to existing: \(existingConversation.id)")
            state = .existing(id: existingConversation.id)
        } else {
            Logger.info("No existing conversation found, staying in draft state")
            state = .draft(id: draftConversationId)
        }
    }

    func remove(profile: MemberProfile) async throws {
        Logger.info("Removing profile \(profile.inboxId) from draft conversation")
        guard state.canEditMembers else {
            throw DraftConversationWriterError.modifyingMembersOnExistingConversation
        }

        let conversationMember: DBConversationMember? = try await databaseReader.read { [weak self] db in
            guard let self else { return nil }
            return try DBConversationMember
                .filter(Column("conversationId") == draftConversationId)
                .filter(Column("memberId") == profile.inboxId)
                .fetchOne(db)
        }
        guard let conversationMember else {
            throw DraftConversationWriterError.missingProfileForRemoving
        }
        let conversation: DBConversation? = try await databaseReader.read { [weak self] db in
            guard let self else { return nil }
            return try DBConversation
                .filter(Column("clientConversationId") == draftConversationId)
                .fetchOne(db)
        }
        guard let conversation else {
            throw DraftConversationWriterError.failedFindingConversation
        }

        let membersCount: Int = try await databaseReader.read { db in
            try conversation.request(for: DBConversation.memberProfiles).fetchCount(db)
        }
        let updatedConversation = conversation.with(kind: membersCount - 1 <= 1 ? .dm : .group)
        Logger.info("Updated kind to: \(updatedConversation.kind) (remaining members: \(membersCount - 1))")

        _ = try await databaseWriter.write { db in
            try conversationMember.delete(db)
            try updatedConversation.save(db)
            Logger.info("Deleted conversation member and updated conversation in database")
        }

        if let existingConversation = try await findMatchingConversation() {
            Logger.info("Found existing conversation, changing state to existing: \(existingConversation.id)")
            state = .existing(id: existingConversation.id)
        } else {
            Logger.info("No existing conversation found, staying in draft state")
            state = .draft(id: draftConversationId)
        }
    }

    func send(text: String) async throws {
        guard let client = clientValue.value else {
            throw InboxStateError.inboxNotReady
        }

        isSendingValue.send(true)

        defer {
            isSendingValue.send(false)
        }

        let conversation: DBConversation? = try await databaseReader.read { [weak self] db in
            guard let self else { return nil }
            return try DBConversation
                .filter(Column("clientConversationId") == conversationId)
                .fetchOne(db)
        }

        guard let conversation else {
            throw DraftConversationWriterError.failedFindingConversation
        }

        switch state {
        case .existing(let id), .created(let id):
            // send the message
            let messageWriter = OutgoingMessageWriter(
                client: client,
                clientPublisher: clientPublisher,
                databaseWriter: databaseWriter,
                conversationId: id
            )

            try await messageWriter.send(text: text)
            sentMessageSubject.send(text)
        case .draft:
            // save a temporary message to the draft conversation
            try await databaseWriter.write { [weak self] db in
                guard let self else { return }

                let creatorProfile = MemberProfile(
                    inboxId: client.inboxId,
                    name: "",
                    username: "",
                    avatar: nil,
                )
                try creatorProfile.insert(db, onConflict: .ignore)

                // add the current user as a member
                let conversationMember = DBConversationMember(
                    conversationId: conversationId,
                    memberId: client.inboxId,
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

            let inboxId = client.inboxId
            let memberProfiles: [MemberProfile] = try await databaseReader.read { [inboxId] db in
                try conversation
                    .request(for: DBConversation.memberProfiles)
                    .filter(Column("inboxId") != inboxId)
                    .fetchAll(db)
            }

            let externalConversationId: String
            if memberProfiles.count == 1,
               let inboxId = memberProfiles.first?.inboxId {
                externalConversationId = try await client.newConversation(
                    with: inboxId
                )
            } else {
                externalConversationId = try await client.newConversation(
                    with: memberProfiles.map { $0.inboxId },
                    name: "",
                    description: "",
                    imageUrl: ""
                )
            }
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
            _ = try await createdConversation.prepare(text: text)
            try await createdConversation.publish()

            sentMessageSubject.send(text)
        }
    }
}
