import Combine
import Foundation
import GRDB
import XMTPiOS

final class MessagingService: MessagingServiceProtocol {
    private let databaseReader: any DatabaseReader
    private let databaseWriter: any DatabaseWriter
    private let stateMachine: MessagingServiceStateMachine
    private let apiClient: any ConvosAPIClientProtocol

    var state: MessagingServiceState {
        stateMachine.state
    }

    var messagingStatePublisher: AnyPublisher<MessagingServiceState, Never> {
        stateMachine.statePublisher
    }

    init(authService: any AuthServiceProtocol,
         databaseWriter: any DatabaseWriter,
         databaseReader: any DatabaseReader,
         apiClient: any ConvosAPIClientProtocol,
         environment: MessagingServiceEnvironment) {
        let userWriter = UserWriter(databaseWriter: databaseWriter)
        let syncingManager = SyncingManager(databaseWriter: databaseWriter,
                                            apiClient: apiClient)
        self.stateMachine = MessagingServiceStateMachine(
            authService: authService,
            apiClient: apiClient,
            userWriter: userWriter,
            syncingManager: syncingManager,
            environment: environment
        )
        self.apiClient = apiClient
        self.databaseReader = databaseReader
        self.databaseWriter = databaseWriter
    }

    // MARK: User

    func userRepository() -> any UserRepositoryProtocol {
        UserRepository(dbReader: databaseReader)
    }

    // MARK: Profile Search

    func profileSearchRepository() -> any ProfileSearchRepositoryProtocol {
        ProfileSearchRepository(
            apiClient: apiClient,
            clientPublisher: stateMachine.clientPublisher
        )
    }

    // MARK: Conversations

    func draftConversationComposer() -> any DraftConversationComposerProtocol {
        let clientConversationId: String = DBConversation.generateDraftConversationId()
        let draftConversationWriter = DraftConversationWriter(
            clientPublisher: stateMachine.clientPublisher,
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
                apiClient: apiClient,
                clientPublisher: stateMachine.clientPublisher
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
        ConversationConsentWriter(databaseWriter: databaseWriter, clientPublisher: clientPublisher)
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
        OutgoingMessageWriter(clientPublisher: stateMachine.clientPublisher,
                              databaseWriter: databaseWriter,
                              conversationId: conversationId)
    }

    // MARK: State Machine

    var clientPublisher: AnyPublisher<(any XMTPClientProvider)?, Never> {
        stateMachine.clientPublisher
    }

    func start() async throws {
        try await stateMachine.start()
    }

    func stop() async {
        await stateMachine.stop()
    }
}
