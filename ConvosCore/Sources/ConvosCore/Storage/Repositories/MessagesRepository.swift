import Combine
import Foundation
import GRDB

public typealias ConversationMessages = (conversationId: String, messages: [AnyMessage])

public protocol MessagesRepositoryProtocol {
    var messagesPublisher: AnyPublisher<[AnyMessage], Never> { get }
    var conversationMessagesPublisher: AnyPublisher<ConversationMessages, Never> { get }

    func fetchAll() throws -> [AnyMessage]
}

extension MessagesRepositoryProtocol {
    var messagesPublisher: AnyPublisher<[AnyMessage], Never> {
        conversationMessagesPublisher
            .map { $0.messages }
            .eraseToAnyPublisher()
    }
}

class MessagesRepository: MessagesRepositoryProtocol {
    private let dbReader: any DatabaseReader
    private var conversationId: String {
        conversationIdSubject.value
    }
    private let conversationIdSubject: CurrentValueSubject<String, Never>
    private let messages: [AnyMessage] = []
    private var conversationIdCancellable: AnyCancellable?

    init(dbReader: any DatabaseReader, conversationId: String) {
        self.dbReader = dbReader
        self.conversationIdSubject = .init(conversationId)
    }

    init(dbReader: any DatabaseReader,
         conversationId: String,
         conversationIdPublisher: AnyPublisher<String, Never>) {
        self.dbReader = dbReader
        self.conversationIdSubject = .init(conversationId)
        conversationIdCancellable = conversationIdPublisher.sink { [weak self] conversationId in
            guard let self else { return }
            Logger.info("Sending updated conversation id: \(conversationId)")
            conversationIdSubject.send(conversationId)
        }
    }

    deinit {
        conversationIdCancellable?.cancel()
    }

    func fetchAll() throws -> [AnyMessage] {
        try dbReader.read { [weak self] db in
            guard let self else { return [] }
            return try db.composeMessages(for: conversationId)
        }
    }

    lazy var conversationMessagesPublisher: AnyPublisher<ConversationMessages, Never> = {
        conversationIdSubject
            .removeDuplicates()
            .map { [weak self] conversationId -> AnyPublisher<ConversationMessages, Never> in
                guard let self else {
                    return Just((conversationId, [])).eraseToAnyPublisher()
                }

                return ValueObservation
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
                    .map { (conversationId, $0) }
                    .eraseToAnyPublisher()
            }
            .switchToLatest()
            .eraseToAnyPublisher()
    }()
}

extension Array where Element == MessageWithDetails {
    func composeMessages(from database: Database,
                         in conversation: Conversation) throws -> [AnyMessage] {
        let dbMessagesWithDetails = self

        return try dbMessagesWithDetails.compactMap { dbMessageWithDetails -> AnyMessage? in
            let dbMessage = dbMessageWithDetails.message
            let dbReactions = dbMessageWithDetails.messageReactions
            let dbSender = dbMessageWithDetails.messageSender

            let sender = dbSender.hydrateConversationMember(currentInboxId: conversation.inboxId)
            let source: MessageSource = sender.isCurrentUser ? .outgoing : .incoming
            let reactions: [MessageReaction] = dbReactions.map {
                .init(
                    id: $0.clientMessageId,
                    conversation: conversation,
                    sender: sender,
                    source: source,
                    status: $0.status,
                    content: .emoji($0.emoji ?? ""),
                    date: Date(),
                    emoji: $0.emoji ?? ""
                )
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
                case .update:
                    guard let update = dbMessage.update,
                          let initiatedByMember = try MemberProfile.fetchOne(
                            database,
                            key: update.initiatedByInboxId
                          ) else {
                        Logger.error("Update message type is missing update object")
                        return nil
                    }
                    let addedMembers = try MemberProfile.fetchAll(database, keys: update.addedInboxIds)
                    let removedMembers = try MemberProfile.fetchAll(database, keys: update.removedInboxIds)
                    messageContent = .update(
                        .init(
                            creator: initiatedByMember.hydrateProfile(),
                            addedMembers: addedMembers.map { $0.hydrateProfile() },
                            removedMembers: removedMembers.map { $0.hydrateProfile() },
                            metadataChanges: update.metadataChanges
                                .map {
                                    .init(
                                        field: .init(rawValue: $0.field) ?? .unknown,
                                        oldValue: $0.oldValue,
                                        newValue: $0.newValue
                                    )
                                }
                        )
                    )
                }

                let message = Message(id: dbMessage.clientMessageId,
                                      conversation: conversation,
                                      sender: sender,
                                      source: source,
                                      status: dbMessage.status,
                                      content: messageContent,
                                      date: dbMessage.date,
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
        guard let dbConversationDetails = try DBConversation
            .filter(Column("id") == conversationId)
            .detailedConversationQuery()
            .fetchOne(self) else {
            return []
        }

        let conversation = dbConversationDetails.hydrateConversation()
        let dbMessages = try DBMessage
            .filter(Column("conversationId") == conversationId)
            .including(
                required: DBMessage.sender
                    .forKey("messageSender")
                    .select([DBConversationMember.Columns.role])
                    .including(required: DBConversationMember.memberProfile)
            )
            .including(all: DBMessage.reactions)
            // .including(all: DBMessage.replies)
            .including(optional: DBMessage.sourceMessage)
            .asRequest(of: MessageWithDetails.self)
            .fetchAll(self)
        return try dbMessages.composeMessages(from: self, in: conversation)
    }
}
