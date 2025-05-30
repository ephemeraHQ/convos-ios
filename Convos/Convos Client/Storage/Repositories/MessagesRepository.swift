import Combine
import Foundation
import GRDB

protocol MessagesRepositoryProtocol {
    func fetchAll() throws -> [AnyMessage]
    func messagesPublisher() -> AnyPublisher<[AnyMessage], Never>
}

class MessagesRepository: MessagesRepositoryProtocol {
    private let dbReader: any DatabaseReader
    private let conversationId: String
    private let messages: [AnyMessage] = []

    init(dbReader: any DatabaseReader, conversationId: String) {
        self.dbReader = dbReader
        self.conversationId = conversationId
    }

    func fetchAll() throws -> [AnyMessage] {
        try dbReader.read { [weak self] db in
            guard let self else { return [] }
            return try db.composeMessages(for: conversationId)
        }
    }

    func messagesPublisher() -> AnyPublisher<[AnyMessage], Never> {
        ValueObservation
            .tracking { [weak self] db in
                guard let self else { return [] }
                do {
                    let messages = try db.composeMessages(for: conversationId)
                    return messages
                } catch {
                    Logger.error("Error in messages publisher: \(error)")
                }
                return []
            }
            .publisher(in: dbReader)
            .replaceError(with: [])
            .eraseToAnyPublisher()
    }
}

extension Array where Element == MessageWithDetails {
    func composeMessages(from database: Database,
                         in conversation: Conversation) throws -> [AnyMessage] {
        let dbMessagesWithDetails = self

        guard let currentUser = try database.currentUser() else {
            return []
        }

        return dbMessagesWithDetails.compactMap { dbMessageWithDetails -> AnyMessage? in
            let dbMessage = dbMessageWithDetails.message
            let dbReactions = dbMessageWithDetails.messageReactions
            let dbSender = dbMessageWithDetails.messageSenderProfile
            let sender: Profile = dbSender.hydrateProfile()
            let isCurrentUser: Bool = dbSender.inboxId == currentUser.inboxId
            let source: MessageSource = isCurrentUser ? .outgoing : .incoming
            let reactions: [MessageReaction] = dbReactions.map {
                .init(id: $0.clientMessageId,
                      conversation: conversation,
                      sender: sender,
                      source: source,
                      status: $0.status,
                      content: .emoji($0.emoji ?? ""),
                      emoji: $0.emoji ?? "")
            }
            switch dbMessage.messageType {
            case .original:
                let messageContent: MessageContent
                switch dbMessage.contentType {
                case .text, .update:
                    messageContent = .text(dbMessage.text ?? "")
                case .attachments:
                    messageContent = .attachments(dbMessage.attachmentUrls.compactMap { urlString in
                        URL(string: urlString)
                    })
                case .emoji:
                    messageContent = .emoji(dbMessage.emoji ?? "")
                }

                let message = Message(id: dbMessage.clientMessageId,
                                      conversation: conversation,
                                      sender: sender,
                                      source: source,
                                      status: dbMessage.status,
                                      content: messageContent,
                                      reactions: reactions)
                return .message(message)
            case .reply:
                switch dbMessage.contentType {
                case .text:
                    break
                case .attachments:
                    break
                case .emoji:
                    break
                case .update:
                    return nil
                }

            case .reaction:
                switch dbMessage.contentType {
                case .text, .attachments, .update:
                    // invalid
                    return nil
                case .emoji:
                    break
                }
            }

            return nil
        }
    }
}

fileprivate extension Database {
    func composeMessages(for conversationId: String) throws -> [AnyMessage] {
        guard let currentUser = try currentUser() else {
            return []
        }

        guard let dbConversationDetails = try DBConversation
            .filter(Column("id") == conversationId)
            .including(required: DBConversation.creatorProfile)
            .including(required: DBConversation.localState)
            .including(all: DBConversation.memberProfiles)
            .asRequest(of: DBConversationDetails.self)
            .fetchOne(self) else {
            return []
        }

        let conversation = dbConversationDetails.hydrateConversation(
            currentUser: currentUser
        )
        let dbMessages = try DBMessage
            .filter(Column("conversationId") == conversationId)
            .including(required: DBMessage.senderProfile)
            .including(all: DBMessage.reactions)
            // .including(all: DBMessage.replies)
            .including(optional: DBMessage.sourceMessage)
            .asRequest(of: MessageWithDetails.self)
            .fetchAll(self)
        return try dbMessages.composeMessages(from: self, in: conversation)
    }
}
