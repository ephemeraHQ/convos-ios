import Combine
import Foundation
import GRDB
import XMTPiOS

protocol OutgoingMessageWriterProtocol {
    func send(text: String) async throws
}

class OutgoingMessageWriter: OutgoingMessageWriterProtocol {
    enum OutgoingMessageWriterError: Error {
        case missingClientProvider
    }

    private weak var clientProvider: XMTPClientProvider?
    private var cancellable: AnyCancellable?
    private let databaseWriter: any DatabaseWriter
    private let conversationId: String

    init(clientProvider: XMTPClientProvider,
         databaseWriter: any DatabaseWriter,
         conversationId: String) {
        self.clientProvider = clientProvider
        self.databaseWriter = databaseWriter
        self.conversationId = conversationId
    }

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

    deinit {
        cancellable?.cancel()
    }

    func send(text: String) async throws {
        guard let sender = try await clientProvider?.messageSender(
            for: conversationId
        ) else {
            throw OutgoingMessageWriterError.missingClientProvider
        }

        let clientMessageId: String = try await sender.prepare(text: text)

        try await databaseWriter.write { [weak self] db in
            guard let self else { return }

            guard let currentUser = try db.currentUser() else {
                throw CurrentSessionError.missingCurrentUser
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
                attachmentUrls: [],
                update: nil
            )

            try localMessage.save(db)
            Logger.info("Saved local message with local id: \(localMessage.clientMessageId)")
        }

        Task {
            Logger.info("Sending local message with local id: \(clientMessageId)")
            try await sender.publish()
            Logger.info("Sent local message with local id: \(clientMessageId)")
        }
    }
}
