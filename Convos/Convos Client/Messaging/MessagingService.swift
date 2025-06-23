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

    // MARK: Profile Search

    func profileSearchRepository() -> any ProfileSearchRepositoryProtocol {
        ProfileSearchRepository(
            inboxReady: inboxReadyValue.value,
            inboxReadyPublisher: inboxReadyPublisher
        )
    }

    // MARK: Conversations

    func draftConversationComposer() -> any DraftConversationComposerProtocol {
        let clientConversationId: String = DBConversation.generateDraftConversationId()
        let draftConversationWriter = DraftConversationWriter(
            client: clientValue.value,
            clientPublisher: clientPublisher,
            databaseReader: databaseReader,
            databaseWriter: databaseWriter,
            draftConversationId: clientConversationId
        )
        return DraftConversationComposer(
            draftConversationWriter: draftConversationWriter,
            draftConversationRepository: DraftConversationRepository(
                dbReader: databaseReader,
                writer: draftConversationWriter
            ),
            profileSearchRepository: ProfileSearchRepository(
                inboxReady: inboxReadyValue.value,
                inboxReadyPublisher: inboxReadyPublisher
            ),
            conversationConsentWriter: conversationConsentWriter(),
            conversationLocalStateWriter: conversationLocalStateWriter()
        )
    }

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
}
