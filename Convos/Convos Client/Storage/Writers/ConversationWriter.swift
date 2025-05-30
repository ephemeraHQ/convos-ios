import Foundation
import GRDB
import XMTPiOS

protocol ConversationWriterProtocol {
    @discardableResult
    func store(conversation: XMTPiOS.Conversation) async throws -> DBConversation
}

class ConversationWriter: ConversationWriterProtocol {
    private let databaseWriter: any DatabaseWriter
    private let messageWriter: any IncomingMessageWriterProtocol

    init(databaseWriter: any DatabaseWriter,
         messageWriter: any IncomingMessageWriterProtocol) {
        self.databaseWriter = databaseWriter
        self.messageWriter = messageWriter
    }

    @discardableResult
    func store(conversation: XMTPiOS.Conversation) async throws -> DBConversation {
        let dbMembers: [DBConversationMember] = try await conversation.members()
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
            isUnread: false,
            isMuted: false
        )

        let lastMessage = try await conversation.lastMessage()
        let dbConversation = DBConversation(
            id: conversation.id,
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
            name: "",
            username: "",
            avatar: nil,
        )

        try await databaseWriter.write { db in
            try creator.save(db)
            try creatorProfile.save(db)

            try dbConversation.save(db)

            try localState.save(db)

            for member in dbMembers {
                try Member(inboxId: member.memberId).save(db)
                try member.save(db)
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
              memberId: inboxId,
              role: permissionLevel.role,
              consent: consentState.memberConsent)
    }
}

fileprivate extension XMTPiOS.PermissionLevel {
    var role: DBConversationMember.Role {
        switch self {
        case .SuperAdmin: return .superAdmin
        case .Admin: return .admin
        case .Member: return .member
        }
    }
}

fileprivate extension XMTPiOS.Conversation {
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
    var memberConsent: DBConversationMember.Consent {
        switch self {
        case .allowed: return .allowed
        case .denied: return .denied
        case .unknown: return .unknown
        }
    }

    var consent: DBConversation.Consent {
        switch self {
        case .allowed: return .allowed
        case .denied: return .denied
        case .unknown: return .unknown
        }
    }
}
