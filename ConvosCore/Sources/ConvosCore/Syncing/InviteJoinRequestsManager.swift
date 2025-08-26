import Foundation
import GRDB
import XMTPiOS

protocol InviteJoinRequestsManagerProtocol {
    func start(with client: AnyClientProvider,
               apiClient: any ConvosAPIClientProtocol)
    func stop()
}

class InviteJoinRequestsManager: InviteJoinRequestsManagerProtocol {
    private let databaseReader: any DatabaseReader
    private let conversationWriter: any ConversationWriterProtocol

    private var streamMessagesTask: Task<Void, Never>?

    init(databaseReader: any DatabaseReader,
         databaseWriter: any DatabaseWriter) {
        self.databaseReader = databaseReader
        let messageWriter = IncomingMessageWriter(databaseWriter: databaseWriter)
        self.conversationWriter = ConversationWriter(databaseWriter: databaseWriter,
                                                     messageWriter: messageWriter)
    }

    deinit {
        streamMessagesTask?.cancel()
        streamMessagesTask = nil
    }

    func start(with client: AnyClientProvider,
               apiClient: any ConvosAPIClientProtocol) {
        streamMessagesTask = Task { [weak self, client] in
            do {
                Logger.info("Started streaming messages...")
                for try await message in client.conversationsProvider
                    .streamAllMessages(
                        type: .dms,
                        consentStates: [.unknown],
                        onClose: {
                            Logger.warning("Closing streamAllMessages...")
                        }
                    ) {
                    guard let self else { return }
                    do {
                        let dbMessage = try message.dbRepresentation()
                        guard let inviteCode = dbMessage.text else {
                            continue
                        }
                        let dbConversation: DBConversation? = try await databaseReader.read { db in
                            guard let invite = try DBInvite
                                .fetchOne(db, key: inviteCode) else {
                                Logger.warning("Invite code not found for incoming message content")
                                return nil
                            }

                            guard let conversation = try DBConversation
                                .fetchOne(db, key: invite.conversationId) else {
                                Logger.warning("Conversation not found for invite")
                                return nil
                            }

                            return conversation
                        }

                        guard let dbConversation else {
                            continue
                        }

                        guard let conversation = try await client.conversationsProvider.findConversation(
                            conversationId: dbConversation.id
                        ) else {
                            Logger.warning("Conversation not found on XMTP")
                            continue
                        }

                        switch conversation {
                        case .group(let group):
                            Logger.info("Adding \(message.senderInboxId) to group \(group.id)...")
                            try await group.add(members: [message.senderInboxId])
                            Logger.info("Storing conversation with id: \(conversation.id)")
                            try await conversationWriter.store(conversation: conversation)
                        case .dm:
                            Logger.warning("Expected Group but found DM, ignoring invite join request...")
                        }
                    } catch {
                        Logger.error("Error decoding message: \(error.localizedDescription)")
                    }
                }
            } catch {
                Logger.error("Error streaming all messages: \(error)")
            }
        }
    }

    func stop() {
        streamMessagesTask?.cancel()
    }
}
