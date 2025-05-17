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
        let dbConversation = DBConversation(
            id: conversation.id,
            isCreator: try await conversation.isCreator(),
            kind: kind,
            consent: try conversation.consentState().consent,
            createdAt: conversation.createdAt,
            topic: conversation.topic,
            creatorId: try await conversation.creatorInboxId,
            memberIds: dbMembers.map { $0.id },
            imageURLString: imageURLString
        )

        let isCurrentUser = conversation.client.inboxID == dbConversation.creatorId
        let creatorProfile = MemberProfile(
            inboxId: dbConversation.creatorId,
            name: "",
            username: "",
            avatar: nil,
            isCurrentUser: isCurrentUser
        )

        let lastMessage = try await conversation.lastMessage()

        try await databaseWriter.write { db in
            try creatorProfile.save(db)

            if let lastMessage {
                let dbLastMessage = try lastMessage.dbRepresentation(
                    conversationId: conversation.id,
                    sender: .empty
                )
                if let dbLastMessage = dbLastMessage as? any PersistableRecord {
                    try dbLastMessage.save(db)
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

fileprivate extension XMTPiOS.DecodedMessage {
    enum DecodedMessageDBRepresentationError: Error {
        case mismatchedContentType, unsupportedContentType
    }

    func dbRepresentation(conversationId: String,
                          sender: Profile) throws -> any MessageType {
        let senderId = senderInboxId
        let source: MessageSource = sender.isCurrentUser ? .outgoing : .incoming
        let status: MessageStatus = deliveryStatus.status

        let content = try content() as Any
        let encodedContentType = try encodedContent.type
        switch encodedContentType {
        case ContentTypeText:
            guard let contentString = content as? String else {
                throw DecodedMessageDBRepresentationError.mismatchedContentType
            }
            let kind: MessageKind = .text(contentString)
            return Message(id: id,
                           conversationId: conversationId,
                           sender: sender,
                           date: sentAt,
                           kind: kind,
                           source: source,
                           status: status)
        case ContentTypeReply:
            guard let contentReply = content as? Reply else {
                throw DecodedMessageDBRepresentationError.mismatchedContentType
            }
            let sourceMessageId = contentReply.reference
            let kind: MessageKind
            switch contentReply.contentType {
            case ContentTypeText:
                guard let contentString = contentReply.content as? String else {
                    throw DecodedMessageDBRepresentationError.mismatchedContentType
                }
                kind = .text(contentString)
            case ContentTypeRemoteAttachment:
                guard let remoteAttachment = content as? RemoteAttachment else {
                    throw DecodedMessageDBRepresentationError.mismatchedContentType
//                      let encodedContent: EncodedContent = try? await remoteAttachment.content(),
//                      let attachment: Attachment = try? encodedContent.decoded(),
//                      let localURL = try? attachment.saveToTmpFile() else {
                }
                kind = .attachment(URL(string: "http://google.com")!)
            default:
                Logger.error("Unhandled contentType \(contentReply.contentType)")
                kind = .text("")
            }
            return MessageReply(id: id,
                                conversationId: conversationId,
                                sender: sender,
                                date: sentAt,
                                kind: kind,
                                source: source,
                                status: status,
                                sourceMessageId: sourceMessageId)
        case ContentTypeReaction, ContentTypeReactionV2:
            guard let reaction = content as? Reaction else {
                throw DecodedMessageDBRepresentationError.mismatchedContentType
            }
            return MessageReaction(id: id,
                                   conversationId: conversationId,
                                   sender: sender,
                                   date: sentAt,
                                   source: source,
                                   status: status,
                                   sourceMessageId: reaction.reference,
                                   emoji: reaction.emoji)
        case ContentTypeRemoteAttachment:
            guard let remoteAttachment = content as? RemoteAttachment else {
                throw DecodedMessageDBRepresentationError.mismatchedContentType
            }
            return Message(id: id,
                           conversationId: conversationId,
                           sender: sender,
                           date: sentAt,
                           kind: .attachment(URL(string: "http://google.com")!),
                           source: source,
                           status: status)
        case ContentTypeAttachment:
            throw DecodedMessageDBRepresentationError.unsupportedContentType
        default:
            throw DecodedMessageDBRepresentationError.unsupportedContentType
        }
    }
}

fileprivate extension XMTPiOS.Reaction {
    var emoji: String {
        switch schema {
        case .unicode:
            if let scalarValue = UInt32(content.replacingOccurrences(of: "U+", with: ""), radix: 16),
               let scalar = UnicodeScalar(scalarValue) {
                return String(scalar)
            }
        default:
            break
        }
        return content
    }
}

fileprivate extension XMTPiOS.MessageDeliveryStatus {
    var status: MessageStatus {
        switch self {
        case .failed: return .failed
        case .unpublished: return .unpublished
        case .published: return .published
        case .all: return .unknown
        }
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
