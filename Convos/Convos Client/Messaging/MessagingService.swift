import Combine
import Foundation
import GRDB
import XMTPiOS

final class MessagingService: MessagingServiceProtocol {
    private let client: any XMTPClientProvider
    private let databaseReader: any DatabaseReader
    private let databaseWriter: any DatabaseWriter
    private let apiClient: any ConvosAPIClientProtocol
    private var cancellables: Set<AnyCancellable> = []

    init(client: any XMTPClientProvider,
         apiClient: any ConvosAPIClientProtocol,
         databaseWriter: any DatabaseWriter,
         databaseReader: any DatabaseReader) {
        self.client = client
        self.apiClient = apiClient
        self.databaseReader = databaseReader
        self.databaseWriter = databaseWriter
    }

    // MARK: Profile Search

    func profileSearchRepository() -> any ProfileSearchRepositoryProtocol {
        ProfileSearchRepository(
            client: client,
            apiClient: apiClient
        )
    }

    // MARK: Conversations

    func draftConversationComposer() -> any DraftConversationComposerProtocol {
        let clientConversationId: String = DBConversation.generateDraftConversationId()
        let draftConversationWriter = DraftConversationWriter(
            client: client,
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
                client: client,
                apiClient: apiClient
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
        ConversationConsentWriter(databaseWriter: databaseWriter, client: client)
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
        OutgoingMessageWriter(client: client,
                              databaseWriter: databaseWriter,
                              conversationId: conversationId)
    }
}
