import Combine
import Foundation
import GRDB

protocol DraftConversationWriterProtocol: OutgoingMessageWriterProtocol {
    // this should just be a publisher for the current conversation
    var selectedConversationId: String? { get set }
    // "selecting" a conversation is really just adding all members from that conversation
    func add(profile: MemberProfile) async throws
    func remove(profile: MemberProfile) async throws
}

class DraftConversationWriter: DraftConversationWriterProtocol {
    enum DraftConversationWriterError: Error {
        case missingClientProvider,
             missingConversationMembers,
             failedFindingConversation,
             missingCurrentUser,
             missingProfileForRemoving
    }

    private let databaseReader: any DatabaseReader
    private let databaseWriter: any DatabaseWriter
    private weak var clientProvider: XMTPClientProvider?
    private var cancellable: AnyCancellable?

    // the conversation id of the conversation we're publishing for the conversation repo
    private var conversationId: String
    // the id of the draft conversation we create when a profile is added
    private let draftConversationId: String
    // the id of the conversation if it has been created on XMTP
    private var createdConversationId: String?
    // we can get rid of this
    var selectedConversationId: String?

    init(clientPublisher: AnyPublisher<XMTPClientProvider?, Never>,
         databaseReader: any DatabaseReader,
         databaseWriter: any DatabaseWriter,
         draftConversationId: String) {
        self.databaseReader = databaseReader
        self.databaseWriter = databaseWriter
        self.draftConversationId = draftConversationId
        self.conversationId = draftConversationId
        cancellable = clientPublisher.sink { [weak self] clientProvider in
            guard let self else { return }
            self.clientProvider = clientProvider
        }
    }

    func add(profile: MemberProfile) async throws {
        let conversationMember = DBConversationMember(
            conversationId: conversationId,
            memberId: profile.inboxId,
            role: .member,
            consent: .allowed,
            createdAt: Date()
        )
        let member = Member(inboxId: profile.inboxId)
        let conversation: DBConversation? = try await databaseReader.read { [weak self] db in
            guard let self else { return nil }
            if let existing = try DBConversation.filter(Column("clientConversationId") == conversationId).fetchOne(db) {
                return existing
            } else {
                guard let currentUser = try db.currentUser() else {
                    throw DraftConversationWriterError.missingCurrentUser
                }
                return DBConversation(
                    id: conversationId,
                    clientConversationId: conversationId,
                    creatorId: currentUser.inboxId,
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

        // check if there's an existing conversation with the current conversation members
        // plus the one we're adding
        let existingConversation: DBConversation? = try await databaseReader.read { db in
            var memberInboxIds = try conversation.request(for: DBConversation.memberProfiles)
                .fetchAll(db)
                .map { $0.inboxId }
            memberInboxIds.append(profile.inboxId)
            guard let conversationsRequest = DBConversation.findConversationWith(
                members: memberInboxIds
            ) else {
                return nil
            }

            let conversations: [DBConversation] = try conversationsRequest.fetchAll(db)
            return conversations.first
        }
        // if we've found an existing conversation with those members, we need to publish it
        // so the messages repository publishes those messages

        let membersCount: Int = try await databaseReader.read { db in
            try conversation.request(for: DBConversation.memberProfiles).fetchCount(db)
        }
        let updatedConversation = conversation.with(kind: (membersCount + 1) == 1 ? .dm : .group)

        try await databaseWriter.write { db in
            try member.save(db)
            try profile.save(db)
            try updatedConversation.save(db)
            let localState = ConversationLocalState(
                conversationId: conversation.id,
                isPinned: false,
                isUnread: false,
                isMuted: false
            )
            try localState.save(db)
            try conversationMember.save(db)
        }
    }

    func remove(profile: MemberProfile) async throws {
        let conversationMember: DBConversationMember? = try await databaseReader.read { [weak self] db in
            guard let self else { return nil }
            return try DBConversationMember
                .filter(Column("conversationId") == conversationId)
                .filter(Column("memberId") == profile.inboxId)
                .fetchOne(db)
        }
        guard let conversationMember else {
            throw DraftConversationWriterError.missingProfileForRemoving
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
        let membersCount: Int = try await databaseReader.read { db in
            try conversation.request(for: DBConversation.memberProfiles).fetchCount(db)
        }
        let updatedConversation = conversation.with(kind: membersCount - 1 <= 1 ? .dm : .group)

        _ = try await databaseWriter.write { db in
            try conversationMember.delete(db)
            try updatedConversation.save(db)
        }
    }

    func send(text: String) async throws {
        guard let clientProvider else {
            throw DraftConversationWriterError.missingClientProvider
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

        // save a temporary message to the draft conversation
        if createdConversationId == nil {
            try await databaseWriter.write { [weak self] db in
                guard let self else { return }

                guard let currentUser = try db.currentUser() else {
                    throw CurrentSessionError.missingCurrentUser
                }

                let creatorProfile = MemberProfile(
                    inboxId: currentUser.inboxId,
                    name: "",
                    username: "",
                    avatar: nil,
                )
                try creatorProfile.insert(db, onConflict: .ignore)

                // add the current user as a member
                let conversationMember = DBConversationMember(
                    conversationId: conversationId,
                    memberId: currentUser.inboxId,
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
                    senderId: currentUser.inboxId,
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
        }

        Task {
            let memberProfiles: [MemberProfile] = try await databaseReader.read { db in
                guard let currentUser = try db.currentUser() else {
                    throw CurrentSessionError.missingCurrentUser
                }

                return try conversation
                    .request(for: DBConversation.memberProfiles)
                    .filter(Column("inboxId") != currentUser.inboxId)
                    .fetchAll(db)
            }

            if let createdConversationId {
                // send the message
                let messageWriter = OutgoingMessageWriter(clientProvider: clientProvider,
                                                          databaseWriter: databaseWriter,
                                                          conversationId: createdConversationId)

                try await messageWriter.send(text: text)
            } else {
                // create the conversation
                let externalConersationId: String
                if memberProfiles.count == 1,
                   let inboxId = memberProfiles.first?.inboxId {
                    externalConersationId = try await clientProvider.newConversation(
                        with: inboxId
                    )
                } else {
                    externalConersationId = try await clientProvider.newConversation(
                        with: memberProfiles.map { $0.inboxId },
                        name: "",
                        description: "",
                        imageUrl: ""
                    )
                }
                createdConversationId = externalConersationId

                guard let createdConversation = try await clientProvider.conversation(
                    with: externalConersationId
                ) else {
                    throw DraftConversationWriterError.failedFindingConversation
                }

                let draftConversation = try await databaseReader.read { [weak self] db -> DBConversation? in
                    guard let self else { return nil }
                    return try DBConversation.fetchOne(db, key: draftConversationId)
                }?.with(id: externalConersationId)
                try await databaseWriter.write { db in
                    try draftConversation?.save(db)
                }

                let messageWriter = IncomingMessageWriter(databaseWriter: databaseWriter)
                let conversationWriter = ConversationWriter(databaseWriter: databaseWriter,
                                                            messageWriter: messageWriter)
                _ = try await conversationWriter.store(conversation: createdConversation,
                                                       clientConversationId: draftConversationId)
                _ = try await createdConversation.prepare(text: text)
                try await createdConversation.publish()
            }
        }
    }
}
