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

    // MARK: Invites

    func inviteRepository(for conversationId: String) -> any InviteRepositoryProtocol {
        InviteRepository(
            databaseReader: databaseReader,
            conversationId: conversationId,
            conversationIdPublisher: Just(conversationId).eraseToAnyPublisher()
        )
    }

    // MARK: My Profile

    func myProfileRepository() -> any MyProfileRepositoryProtocol {
        MyProfileRepository(inboxReadyValue: inboxReadyValue, databaseReader: databaseReader)
    }

    func myProfileWriter() -> any MyProfileWriterProtocol {
        MyProfileWriter(inboxReadyValue: inboxReadyValue, databaseWriter: databaseWriter)
    }

    // MARK: New Conversation

    func draftConversationComposer() -> any DraftConversationComposerProtocol {
        let clientConversationId: String = DBConversation.generateDraftConversationId()
        let draftConversationWriter = DraftConversationWriter(
            inboxReadyValue: inboxReadyValue,
            databaseReader: databaseReader,
            databaseWriter: databaseWriter,
            draftConversationId: clientConversationId
        )
        return DraftConversationComposer(
            myProfileWriter: myProfileWriter(),
            draftConversationWriter: draftConversationWriter,
            draftConversationRepository: DraftConversationRepository(
                dbReader: databaseReader,
                writer: draftConversationWriter
            ),
            conversationConsentWriter: conversationConsentWriter(),
            conversationLocalStateWriter: conversationLocalStateWriter(),
            conversationMetadataWriter: groupMetadataWriter()
        )
    }

    // MARK: Conversations

    func conversationsRepository(for consent: [Consent]) -> any ConversationsRepositoryProtocol {
        ConversationsRepository(dbReader: databaseReader, consent: consent)
    }

    func conversationsCountRepo(for consent: [Consent], kinds: [ConversationKind]) -> any ConversationsCountRepositoryProtocol {
        ConversationsCountRepository(databaseReader: databaseReader, consent: consent, kinds: kinds)
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

    func groupMetadataWriter() -> any ConversationMetadataWriterProtocol {
        ConversationMetadataWriter(
            inboxReadyValue: inboxReadyValue,
            databaseWriter: databaseWriter
        )
    }

    func groupPermissionsRepository() -> any GroupPermissionsRepositoryProtocol {
        GroupPermissionsRepository(client: clientValue.value,
                                   clientPublisher: clientPublisher,
                                   databaseReader: databaseReader)
    }

    func uploadImage(data: Data, filename: String) async throws -> String {
        guard let inboxReady = inboxReadyValue.value else {
            throw InboxStateError.inboxNotReady
        }

        return try await inboxReady.apiClient.uploadAttachment(
            data: data,
            filename: filename,
            contentType: "image/jpeg",
            acl: "public-read"
        )
    }

    func uploadImageAndExecute(
        data: Data,
        filename: String,
        afterUpload: @escaping (String) async throws -> Void
    ) async throws -> String {
        guard let inboxReady = inboxReadyValue.value else {
            throw InboxStateError.inboxNotReady
        }

        return try await inboxReady.apiClient.uploadAttachmentAndExecute(
            data: data,
            filename: filename,
            afterUpload: afterUpload
        )
    }
}
