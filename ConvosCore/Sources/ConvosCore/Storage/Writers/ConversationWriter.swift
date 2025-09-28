import Foundation
import GRDB
import XMTPiOS

enum ConversationWriterError: Error {
    case inboxNotFound(String)
    case expectedGroup
}

public protocol ConversationWriterProtocol {
    @discardableResult
    func store(conversation: XMTPiOS.Conversation) async throws -> DBConversation
    @discardableResult
    func storeWithLatestMessages(conversation: XMTPiOS.Conversation) async throws -> DBConversation
    func store(conversation: XMTPiOS.Conversation,
               clientConversationId: String) async throws -> DBConversation
}

class ConversationWriter: ConversationWriterProtocol {
    private let databaseWriter: any DatabaseWriter
    private let inviteWriter: any InviteWriterProtocol
    private let messageWriter: any IncomingMessageWriterProtocol
    private let localStateWriter: any ConversationLocalStateWriterProtocol

    init(identityStore: any KeychainIdentityStoreProtocol,
         databaseWriter: any DatabaseWriter,
         messageWriter: any IncomingMessageWriterProtocol) {
        self.databaseWriter = databaseWriter
        self.inviteWriter = InviteWriter(
            identityStore: identityStore,
            databaseWriter: databaseWriter
        )
        self.messageWriter = messageWriter
        self.localStateWriter = ConversationLocalStateWriter(databaseWriter: databaseWriter)
    }

    func store(conversation: XMTPiOS.Conversation) async throws -> DBConversation {
        return try await _store(conversation: conversation)
    }

    func storeWithLatestMessages(conversation: XMTPiOS.Conversation) async throws -> DBConversation {
        return try await _store(conversation: conversation, withLatestMessages: true)
    }

    func store(conversation: XMTPiOS.Conversation, clientConversationId: String) async throws -> DBConversation {
        return try await _store(conversation: conversation, clientConversationId: clientConversationId)
    }

    private func _store(
        conversation: XMTPiOS.Conversation,
        withLatestMessages: Bool = false,
        clientConversationId: String? = nil
    ) async throws -> DBConversation {
        // Extract conversation metadata
        let metadata = try extractConversationMetadata(from: conversation)
        let members = try await conversation.members()
        let dbMembers = members.map { $0.dbRepresentation(conversationId: conversation.id) }
        guard case .group(let group) = conversation else {
            throw ConversationWriterError.expectedGroup
        }
        let memberProfiles = try group.memberProfiles

        // Create database representation
        let dbConversation = try await createDBConversation(
            from: conversation,
            metadata: metadata,
            clientConversationId: clientConversationId
        )

        // Save to database
        try await saveConversationToDatabase(
            dbConversation: dbConversation,
            dbMembers: dbMembers,
            memberProfiles: memberProfiles,
            clientConversationId: clientConversationId
        )

        // Fetch and store latest messages if requested
        if withLatestMessages {
            try await fetchAndStoreLatestMessages(for: conversation, dbConversation: dbConversation)
        }

        // Store last message
        let lastMessage = try await conversation.lastMessage()
        if let lastMessage {
            let result = try await messageWriter.store(
                message: lastMessage,
                for: dbConversation
            )
            Logger.info("Saved last message: \(result)")
        }

        return dbConversation
    }

    // MARK: - Helper Methods

    private struct ConversationMetadata {
        let kind: ConversationKind
        let name: String?
        let description: String?
        let imageURLString: String?
    }

    private func extractConversationMetadata(from conversation: XMTPiOS.Conversation) throws -> ConversationMetadata {
        switch conversation {
        case .dm:
            return ConversationMetadata(
                kind: .dm,
                name: nil,
                description: nil,
                imageURLString: nil
            )
        case .group(let group):
            return ConversationMetadata(
                kind: .group,
                name: try group.name(),
                description: try group.customDescription,
                imageURLString: try group.imageUrl()
            )
        }
    }

    private func createDBConversation(
        from conversation: XMTPiOS.Conversation,
        metadata: ConversationMetadata,
        clientConversationId: String?
    ) async throws -> DBConversation {
        return DBConversation(
            id: conversation.id,
            inboxId: conversation.client.inboxID,
            clientConversationId: clientConversationId ?? conversation.id,
            creatorId: try await conversation.creatorInboxId,
            kind: metadata.kind,
            consent: try conversation.consentState().consent,
            createdAt: conversation.createdAt,
            name: metadata.name,
            description: metadata.description,
            imageURLString: metadata.imageURLString
        )
    }

    private func saveConversationToDatabase(
        dbConversation: DBConversation,
        dbMembers: [DBConversationMember],
        memberProfiles: [MemberProfile],
        clientConversationId: String?
    ) async throws {
        try await databaseWriter.write { [weak self] db in
            guard let self else { return }
            // Save creator
            let creator = Member(inboxId: dbConversation.creatorId)
            try creator.save(db)

            // Save conversation (handle local conversation updates)
            try saveConversation(dbConversation, clientConversationId: clientConversationId, in: db)

            let creatorProfile = MemberProfile(
                conversationId: dbConversation.id,
                inboxId: dbConversation.creatorId,
                name: nil,
                avatar: nil
            )
            try creatorProfile.insert(db, onConflict: .ignore)

            // Save local state
            let localState = ConversationLocalState(
                conversationId: dbConversation.id,
                isPinned: false,
                isUnread: false,
                isUnreadUpdatedAt: Date.distantPast,
                isMuted: false
            )
            try localState.insert(db, onConflict: .ignore)

            // Delete old members
            try MemberProfile
                .filter(MemberProfile.Columns.conversationId == dbConversation.id)
                .deleteAll(db)
            // Save members
            try saveMembers(dbMembers, in: db)
            // Update profiles
            try memberProfiles.forEach { try $0.save(db) }
        }
    }

    private func saveConversation(_ dbConversation: DBConversation, clientConversationId: String?, in db: Database) throws {
        if let localConversation = try DBConversation
            .filter(Column("id") == dbConversation.id)
            .filter(Column("clientConversationId") != clientConversationId)
            .fetchOne(db) {
            // Keep using the same local id
            Logger.info("Found local conversation \(localConversation.clientConversationId) for incoming \(dbConversation.id)")
            let updatedConversation = dbConversation.with(
                clientConversationId: localConversation.clientConversationId
            )
            try updatedConversation.save(db)
            Logger.info("Updated incoming conversation with local \(localConversation.clientConversationId)")
        } else {
            do {
                try dbConversation.save(db)
            } catch {
                Logger.error("Failed saving incoming conversation \(dbConversation.id): \(error)")
                throw error
            }
        }
    }

    private func saveMembers(_ dbMembers: [DBConversationMember], in db: Database) throws {
        for member in dbMembers {
            try Member(inboxId: member.inboxId).save(db)
            try member.save(db)
            // fetch from description
            let memberProfile = MemberProfile(
                conversationId: member.conversationId,
                inboxId: member.inboxId,
                name: nil,
                avatar: nil
            )
            try? memberProfile.insert(db, onConflict: .ignore)
        }
    }

    private func fetchAndStoreLatestMessages(
        for conversation: XMTPiOS.Conversation,
        dbConversation: DBConversation
    ) async throws {
        Logger.info("Attempting to fetch latest messages...")

        // Get the timestamp of the last stored message
        let lastMessageNs = try await getLastMessageTimestamp(for: conversation.id)

        // Fetch new messages
        let messages = try await conversation.messages(afterNs: lastMessageNs)
        guard !messages.isEmpty else { return }

        Logger.info("Found \(messages.count) new messages, catching up...")

        // Store messages and track if conversation should be marked unread
        var marksConversationAsUnread = false
        for message in messages {
            Logger.info("Catching up with message: \(message) sent at: \(message.sentAt.nanosecondsSince1970)")
            let result = try await messageWriter.store(message: message, for: dbConversation)
            if result.contentType.marksConversationAsUnread {
                marksConversationAsUnread = true
            }
            Logger.info("Saved message: \(result)")
        }

        // Update unread status if needed
        if marksConversationAsUnread {
            try await localStateWriter.setUnread(true, for: conversation.id)
        }
    }

    private func getLastMessageTimestamp(for conversationId: String) async throws -> Int64? {
        try await databaseWriter.read { db in
            let lastMessage = DBConversation.association(
                to: DBConversation.lastMessageCTE,
                on: { conversation, lastMessage in
                    conversation.id == lastMessage.conversationId
                }
            ).forKey("latestMessage")
            let result = try DBConversation
                .filter(Column("id") == conversationId)
                .with(DBConversation.lastMessageCTE)
                .including(optional: lastMessage)
                .asRequest(of: DBConversationLatestMessage.self)
                .fetchOne(db)
            return result?.latestMessage?.dateNs
        }
    }
}

// MARK: - Helper Extensions

extension Attachment {
    func saveToTmpFile() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = UUID().uuidString + filename
        let fileURL = tempDir.appendingPathComponent(fileName)
        try data.write(to: fileURL)
        return fileURL
    }
}

fileprivate extension XMTPiOS.Member {
    func dbRepresentation(conversationId: String) -> DBConversationMember {
        .init(conversationId: conversationId,
              inboxId: inboxId,
              role: permissionLevel.role,
              consent: consentState.memberConsent,
              createdAt: Date())
    }
}

fileprivate extension XMTPiOS.PermissionLevel {
    var role: MemberRole {
        switch self {
        case .SuperAdmin: return .superAdmin
        case .Admin: return .admin
        case .Member: return .member
        }
    }
}

extension XMTPiOS.Conversation {
    var creatorInboxId: String {
        get async throws {
            switch self {
            case .group(let group):
                return try await group.creatorInboxId()
            case .dm(let dm):
                return try await dm.creatorInboxId()
            }
        }
    }
}

fileprivate extension XMTPiOS.ConsentState {
    var memberConsent: Consent {
        switch self {
        case .allowed: return .allowed
        case .denied: return .denied
        case .unknown: return .unknown
        }
    }

    var consent: Consent {
        switch self {
        case .allowed: return .allowed
        case .denied: return .denied
        case .unknown: return .unknown
        }
    }
}
