import Combine
import Foundation
import GRDB
import XMTPiOS

public protocol OutgoingMessageWriterProtocol {
    var isSendingPublisher: AnyPublisher<Bool, Never> { get }
    var sentMessage: AnyPublisher<String, Never> { get }
    func send(text: String) async throws
}

class OutgoingMessageWriter: OutgoingMessageWriterProtocol {
    enum OutgoingMessageWriterError: Error {
        case missingClientProvider
    }

    private let clientPublisher: AnyClientProviderPublisher
    private let clientValue: PublisherValue<AnyClientProvider>
    private let databaseWriter: any DatabaseWriter
    private let conversationId: String
    private let isSendingValue: CurrentValueSubject<Bool, Never> = .init(false)
    private let sentMessageSubject: PassthroughSubject<String, Never> = .init()

    var isSendingPublisher: AnyPublisher<Bool, Never> {
        isSendingValue.eraseToAnyPublisher()
    }

    var sentMessage: AnyPublisher<String, Never> {
        sentMessageSubject.eraseToAnyPublisher()
    }

    init(client: AnyClientProvider?,
         clientPublisher: AnyClientProviderPublisher,
         databaseWriter: any DatabaseWriter,
         conversationId: String) {
        self.clientPublisher = clientPublisher
        self.clientValue = .init(
            initial: client,
            upstream: clientPublisher
        )
        self.databaseWriter = databaseWriter
        self.conversationId = conversationId
    }

    deinit {
        cleanup()
    }

    func cleanup() {
        clientValue.dispose()
    }

    func send(text: String) async throws {
        guard let client = clientValue.value else {
            throw InboxStateError.inboxNotReady
        }

        isSendingValue.send(true)

        defer {
            isSendingValue.send(false)
        }

        guard let sender = try await client.messageSender(
            for: conversationId
        ) else {
            throw OutgoingMessageWriterError.missingClientProvider
        }

        let clientMessageId: String = try await sender.prepare(text: text)

        try await databaseWriter.write { [weak self] db in
            guard let self else { return }

            let localMessage = DBMessage(
                id: clientMessageId,
                clientMessageId: clientMessageId,
                conversationId: conversationId,
                senderId: client.inboxId,
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
            sentMessageSubject.send(text)
            Logger.info("Sent local message with local id: \(clientMessageId)")
        }
    }
}
