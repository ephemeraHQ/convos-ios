import Combine
import Foundation
import GRDB
import XMTPiOS

protocol OutgoingMessageWriterProtocol {
    func send(text: String) async throws
}

class OutgoingMessageWriter: OutgoingMessageWriterProtocol {
    private weak var clientProvider: XMTPClientProvider?
    private var cancellable: AnyCancellable?
    private let databaseWriter: any DatabaseWriter
    private let conversationId: String

    init(clientPublisher: AnyPublisher<XMTPClientProvider?, Never>,
         databaseWriter: any DatabaseWriter,
         conversationId: String) {
        self.databaseWriter = databaseWriter
        self.conversationId = conversationId
        cancellable = clientPublisher.sink { [weak self] clientProvider in
            guard let self else { return }
            self.clientProvider = clientProvider
        }
    }

    func send(text: String) async throws {
        guard let sender = try await clientProvider?.messageSender(for: conversationId) else {
            // TODO: throw error, or add writer 'state'
            return
        }

        let clientMessageId: String = UUID().uuidString

        try await databaseWriter.write { [weak self] db in
            guard let self else { return }

            guard let currentUser = try db.currentUser() else {
                // fail
                return
            }

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
                attachmentUrls: []
            )

            try localMessage.save(db)
            Logger.info("Saved local message with local id: \(localMessage.clientMessageId)")
        }

        Task {
            Logger.info("Sending local message with local id: \(clientMessageId)")
            let messageId = try await sender.send(text: text)
            Logger.info("Sent local message with local id: \(clientMessageId), external id: \(messageId)")
            do {
                try await databaseWriter.write { db in
                    // maybe background stream has published our message
                    if let publishedMessage = try DBMessage
                        .filter(Column("id") == messageId)
                        .filter(Column("clientMessageId") == messageId)
                        .fetchOne(db) {
                        let updatedMessage = publishedMessage.with(
                            clientMessageId: clientMessageId
                        )
                        Logger.info("Found published message with local id: \(clientMessageId)")
                        try updatedMessage.save(db)
                        Logger.info("Updated published clientMessageId from \(messageId) to \(clientMessageId)")
                    } else if let unpublishedMessage = try DBMessage
                        .filter(Column("id") == clientMessageId)
                        .filter(Column("clientMessageId") == clientMessageId)
                        .filter(Column("status") == MessageStatus.unpublished.rawValue)
                        .fetchOne(db) {
                        Logger.info("Found unpublished message with local id: \(clientMessageId)")
                        let updatedMessage = unpublishedMessage.with(
                            id: messageId
                        )
                        try updatedMessage.save(db)
                        Logger.info("Updated local message id from \(clientMessageId) to \(messageId)")
                    } else {
                        Logger.error(
                            "Neither published or unpublished message found for \(clientMessageId) after send"
                        )
                    }
                }
            } catch {
                Logger.error("Error updating local message after sending message: \(error)")
            }
        }
    }
}
