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
                return try db.composeMessages(for: conversationId)
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

        return dbMessagesWithDetails.compactMap { dbMessageWithDetails -> AnyMessage? in
            let dbMessage = dbMessageWithDetails.message
            let dbReactions = dbMessageWithDetails.reactions
            let dbSender = dbMessageWithDetails.sender
            let sender: Profile = dbSender.hydrateProfile()
            let reactions: [MessageReaction] = dbReactions.map {
                .init(id: $0.id,
                      conversation: conversation,
                      sender: sender,
                      status: $0.status,
                      content: .emoji($0.emoji ?? ""),
                      emoji: $0.emoji ?? "")
            }
            switch dbMessage.messageType {
            case .original:
                let messageContent: MessageContent
                switch dbMessage.contentType {
                case .text:
                    messageContent = .text(dbMessage.text ?? "")
                case .attachments:
                    messageContent = .attachments(dbMessage.attachmentUrls.compactMap { urlString in
                        URL(string: urlString)
                    })
                case .emoji:
                    messageContent = .emoji(dbMessage.emoji ?? "")
                }

                let message = Message(id: dbMessage.id,
                                      conversation: conversation,
                                      sender: sender,
                                      status: dbMessage.status,
                                      content: messageContent,
                                      reactions: [])
                return .message(message)
            case .reply:
                switch dbMessage.contentType {
                case .text:
                    break
                case .attachments:
                    break
                case .emoji:
                    break
                }

            case .reaction:
                switch dbMessage.contentType {
                case .text, .attachments:
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

        guard let dbConversation = try DBConversationDetails
            .fetchOne(self, key: conversationId) else {
            return []
        }

        let conversation = dbConversation.hydrateConversation(
            currentUser: currentUser
        )
        let dbMessages = try DBMessage
            .filter(Column("conversationId") == conversationId)
            .including(required: DBMessage.sender)
            .including(required: DBMessage.reactions)
            .asRequest(of: MessageWithDetails.self)
            .fetchAll(self)
        return try dbMessages.composeMessages(from: self, in: conversation)
    }
}
