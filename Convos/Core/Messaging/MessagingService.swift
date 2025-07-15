import Combine
import Foundation
import GRDB
import XMTPiOS

final class MessagingService: MessagingServiceProtocol {
    let inboxReadyPublisher: InboxReadyResultPublisher
    private let inboxReadyValue: PublisherValue<InboxReadyResult>
    private var clientPublisher: AnyClientProviderPublisher {
        inboxReadyPublisher.map(\.client).eraseToAnyPublisher()
    }
    private let clientValue: PublisherValue<AnyClientProvider>
    private let databaseReader: any DatabaseReader
    private let databaseWriter: any DatabaseWriter
    private var cancellables: Set<AnyCancellable> = []

    init(inboxReadyPublisher: InboxReadyResultPublisher,
         databaseWriter: any DatabaseWriter,
         databaseReader: any DatabaseReader) {
        self.clientValue = .init(
            initial: nil,
            upstream: inboxReadyPublisher.map(\.client).eraseToAnyPublisher()
        )
        self.inboxReadyValue = .init(initial: nil, upstream: inboxReadyPublisher)
        self.inboxReadyPublisher = inboxReadyPublisher
        self.databaseReader = databaseReader
        self.databaseWriter = databaseWriter
    }

    // MARK: Conversations

    func conversationsRepository(for consent: [Consent]) -> any ConversationsRepositoryProtocol {
        ConversationsRepository(dbReader: databaseReader, consent: consent)
    }

    func conversationsCountRepo(for consent: [Consent]) -> any ConversationsCountRepositoryProtocol {
        ConversationsCountRepository(databaseReader: databaseReader, consent: consent)
    }

    func conversationRepository(for conversationId: String) -> any ConversationRepositoryProtocol {
        ConversationRepository(conversationId: conversationId,
                               dbReader: databaseReader)
    }

    func conversationConsentWriter() -> any ConversationConsentWriterProtocol {
        ConversationConsentWriter(
            client: clientValue.value,
            clientPublisher: clientPublisher,
            databaseWriter: databaseWriter
        )
    }

    func conversationLocalStateWriter() -> any ConversationLocalStateWriterProtocol {
        ConversationLocalStateWriter(databaseWriter: databaseWriter)
    }

    // MARK: Getting/Sending Messages

    func messagesRepository(for conversationId: String) -> any MessagesRepositoryProtocol {
        MessagesRepository(dbReader: databaseReader,
                           conversationId: conversationId)
    }

    func messageWriter(for conversationId: String) -> any OutgoingMessageWriterProtocol {
        OutgoingMessageWriter(client: clientValue.value,
                              clientPublisher: clientPublisher,
                              databaseWriter: databaseWriter,
                              conversationId: conversationId)
    }

    // MARK: - Group Management

    func groupMetadataWriter() -> any GroupMetadataWriterProtocol {
        GroupMetadataWriter(client: clientValue.value,
                            clientPublisher: clientPublisher,
                            databaseWriter: databaseWriter)
    }

    func groupPermissionsRepository() -> any GroupPermissionsRepositoryProtocol {
        GroupPermissionsRepository(client: clientValue.value,
                                   clientPublisher: clientPublisher,
                                   databaseReader: databaseReader)
    }

    func uploadImage(data: Data, filename: String) async throws -> String {
        // @jarodl fix this
        return ""
//        return try await apiClient.uploadAttachment(
//            data: data,
//            filename: filename,
//            contentType: "image/jpeg",
//            acl: "public-read"
//        )
    }

    func uploadImageAndExecute(
        data: Data,
        filename: String,
        afterUpload: @escaping (String) async throws -> Void
    ) async throws -> String {
        // @jarodl fix this
        return ""
//        return try await apiClient.uploadAttachmentAndExecute(
//            data: data,
//            filename: filename,
//            afterUpload: afterUpload
//        )
    }
}
