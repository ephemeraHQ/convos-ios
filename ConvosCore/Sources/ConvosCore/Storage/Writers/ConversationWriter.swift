import Foundation
import GRDB
import XMTPiOS

enum ConversationWriterError: Error {
    case inboxNotFound(String)
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
    private let messageWriter: any IncomingMessageWriterProtocol

    init(databaseWriter: any DatabaseWriter,
         messageWriter: any IncomingMessageWriterProtocol) {
        self.databaseWriter = databaseWriter
        self.messageWriter = messageWriter
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

    private func _store(conversation: XMTPiOS.Conversation,
                        withLatestMessages: Bool = false,
                        clientConversationId: String? = nil) async throws -> DBConversation {
        let members = try await conversation.members()
        let dbMembers: [DBConversationMember] = members
            .map { $0.dbRepresentation(conversationId: conversation.id) }
        let kind: ConversationKind
        let imageURLString: String?
        let name: String?
        let description: String?
        switch conversation {
        case .dm:
            kind = .dm
            imageURLString = nil
            name = nil
            description = nil
        case .group(let group):
            kind = .group
            name = try? group.name()
            description = try? group.description()
            imageURLString = try? group.imageUrl()
        }

        let localState = ConversationLocalState(
            conversationId: conversation.id,
            isPinned: false,
            isUnread: true,
            isUnreadUpdatedAt: Date.distantPast,
            isMuted: false
        )

        let lastMessage = try await conversation.lastMessage()
        let dbConversation = DBConversation(
            id: conversation.id,
            inboxId: conversation.client.inboxID,
            clientConversationId: clientConversationId ?? conversation.id,
            creatorId: try await conversation.creatorInboxId,
            kind: kind,
            consent: try conversation.consentState().consent,
            createdAt: conversation.createdAt,
            name: name,
            description: description,
            imageURLString: imageURLString
        )

        let creator = Member(inboxId: dbConversation.creatorId)

        let creatorProfile = MemberProfile(
            inboxId: dbConversation.creatorId,
            name: nil,
            avatar: nil,
        )

        try await databaseWriter.write { db in
            try creator.save(db)
            try creatorProfile.insert(db, onConflict: .ignore)

            // Ensure the inbox exists before saving the conversation
            let existingInbox = try DBInbox.filter(DBInbox.Columns.inboxId == dbConversation.inboxId).fetchOne(db)
            if existingInbox == nil {
                Logger.error("Inbox \(dbConversation.inboxId) does not exist, cannot save conversation \(conversation.id)")
                throw ConversationWriterError.inboxNotFound(dbConversation.inboxId)
            }

            // Save the conversation first (conversation_members need to reference it)
            if let localConversation = try DBConversation
                .filter(Column("id") == conversation.id)
                .filter(Column("clientConversationId") != clientConversationId)
                .fetchOne(db) {
                // keep using the same local id
                Logger.info(
                    "Found local conversation \(localConversation.clientConversationId) for incoming \(conversation.id)"
                )
                let updatedConversation = dbConversation.with(
                    clientConversationId: localConversation.clientConversationId
                )
                try updatedConversation.save(db)
                Logger
                    .info(
                        "Updated incoming conversation with local \(localConversation.clientConversationId)"
                    )
            } else {
                do {
                    try dbConversation.save(db)
                } catch {
                    Logger.error("Failed saving incoming conversation \(conversation.id): \(error)")
                    throw error
                }
            }

            try localState.insert(db, onConflict: .ignore)

            for member in dbMembers {
                try Member(inboxId: member.inboxId).save(db)
                try member.save(db)
                let memberProfile = MemberProfile(
                    inboxId: member.inboxId,
                    name: nil,
                    avatar: nil
                )
                try? memberProfile.insert(db, onConflict: .ignore)
            }
        }

        if withLatestMessages {
            Logger.info("Attempting to fetch latest messages...")
            let lastMessageDate: Date? = try await databaseWriter.read { db in
                let lastMessage = DBConversation.association(
                    to: DBConversation.lastMessageCTE,
                    on: { conversation, lastMessage in
                        conversation.id == lastMessage.conversationId
                    }
                ).forKey("latestMessage").order(\.date.desc)
                let result = try DBConversation
                    .filter(Column("id") == conversation.id)
                    .with(DBConversation.lastMessageCTE)
                    .including(optional: lastMessage)
                    .asRequest(of: DBConversationLatestMessage.self)
                    .fetchOne(db)
                return result?.latestMessage?.date
            }
            let afterNs: Int64?
            if let lastMessageDate {
                afterNs = lastMessageDate.nanosecondsSince1970
                Logger.info("Saving conversation with latest messages since: \(afterNs ?? 0)")
            } else {
                afterNs = nil
                Logger.info("Latest message not found, fetching all messages...")
            }
            let messages = try await conversation.messages(afterNs: afterNs)
            for message in messages {
                try await messageWriter.store(message: message, for: dbConversation)
            }
        }

        if let lastMessage {
            try await messageWriter.store(
                message: lastMessage,
                for: dbConversation
            )
        }

        return dbConversation
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
