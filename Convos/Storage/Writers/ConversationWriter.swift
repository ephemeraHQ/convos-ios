import Foundation
import GRDB
import XMTPiOS

protocol ConversationWriterProtocol {
    func store(conversation: XMTPiOS.Conversation) async throws
}

class ConversationWriter: ConversationWriterProtocol {
    private let databaseWriter: any DatabaseWriter

    init(databaseWriter: any DatabaseWriter) {
        self.databaseWriter = databaseWriter
    }

    func store(conversation: XMTPiOS.Conversation) async throws {
        let dbMembers: [Member] = try await conversation.members()
            .map { $0.dbRepresentation(conversationId: conversation.id) }
        let kind: ConversationKind
        let imageURLString: String?
        switch conversation {
        case .dm:
            kind = .dm
            imageURLString = nil
        case .group(let group):
            kind = .group
            imageURLString = try? group.imageUrl()
        }

        let lastMessage = try await conversation.lastMessage()
        let dbLastMessage: MessagePreview?
        if let lastMessage {
            let text = try? lastMessage.body
            dbLastMessage = .init(text: text ?? "",
                                  createdAt: lastMessage.sentAt)
        } else {
            dbLastMessage = nil
        }
        let dbConversation = DBConversation(
            id: conversation.id,
            isCreator: try await conversation.isCreator(),
            kind: kind,
            consent: try conversation.consentState().consent,
            createdAt: conversation.createdAt,
            topic: conversation.topic,
            creatorId: try await conversation.creatorInboxId,
            memberIds: dbMembers.map { $0.inboxId },
            imageURLString: imageURLString,
            lastMessage: dbLastMessage
        )

        let creatorProfile = MemberProfile(
            inboxId: dbConversation.creatorId,
            name: "",
            username: "",
            avatar: nil,
        )

        try await databaseWriter.write { db in
            try creatorProfile.save(db)

            if let lastMessage {
                let dbLastMessage = try lastMessage.dbRepresentation(
                    conversationId: conversation.id,
                    sender: .empty
                )
                if let dbLastMessage = dbLastMessage as? any PersistableRecord {
//                    try dbLastMessage.save(db)
                } else {
                    Logger.error("Error saving last message, could not cast to PersistableRecord")
                }
            }

            try dbConversation.save(db)

            for member in dbMembers {
                try member.save(db)
            }
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
    func dbRepresentation(conversationId: String) -> Member {
        .init(inboxId: inboxId,
              conversationId: conversationId,
              role: permissionLevel.role,
              consent: consentState.memberConsent)
    }
}

fileprivate extension XMTPiOS.PermissionLevel {
    var role: Member.Role {
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
    var memberConsent: Member.Consent {
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
