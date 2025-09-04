import Combine
import Foundation
import GRDB
import XMTPiOS

final class MessagingService: MessagingServiceProtocol {
    var identifier: String {
        guard case .ready(let result) = inboxStateManager.currentState else {
            return internalIdentifier
        }
        return result.client.inboxId
    }
    private let inboxId: String?
    private let internalIdentifier: String
    private let authorizationOperation: any AuthorizeInboxOperationProtocol
    internal let inboxStateManager: InboxStateManager
    private let databaseReader: any DatabaseReader
    internal let databaseWriter: any DatabaseWriter
    private var cancellables: Set<AnyCancellable> = []

    static func authorizedMessagingService(
        for inboxId: String,
        databaseWriter: any DatabaseWriter,
        databaseReader: any DatabaseReader,
        environment: AppEnvironment,
        startsStreamingServices: Bool,
        registersForPushNotifications: Bool = true
    ) -> MessagingService {
        let authorizationOperation = AuthorizeInboxOperation.authorize(
            inboxId: inboxId,
            databaseReader: databaseReader,
            databaseWriter: databaseWriter,
            environment: environment,
            startsStreamingServices: startsStreamingServices,
            registersForPushNotifications: registersForPushNotifications
        )
        return .init(
            inboxId: inboxId,
            authorizationOperation: authorizationOperation,
            databaseWriter: databaseWriter,
            databaseReader: databaseReader
        )
    }

    static func registeredMessagingService(
        databaseWriter: any DatabaseWriter,
        databaseReader: any DatabaseReader,
        environment: AppEnvironment
    ) async -> MessagingService {
        return await UnusedInboxCache.shared.consumeOrCreateMessagingService(
            databaseWriter: databaseWriter,
            databaseReader: databaseReader,
            environment: environment
        )
    }

    internal init(inboxId: String?,
                  authorizationOperation: AuthorizeInboxOperation,
                  databaseWriter: any DatabaseWriter,
                  databaseReader: any DatabaseReader) {
        self.inboxId = inboxId
        self.internalIdentifier = inboxId ?? UUID().uuidString
        self.authorizationOperation = authorizationOperation
        self.inboxStateManager = InboxStateManager(stateMachine: authorizationOperation.stateMachine)
        self.databaseReader = databaseReader
        self.databaseWriter = databaseWriter
    }

    deinit {
        cancellables.removeAll()
    }

    // MARK: State

    func stop() {
        authorizationOperation.stop()
    }

    func stopAndDelete() {
        authorizationOperation.stopAndDelete()
    }

    func stopAndDelete() async {
        await authorizationOperation.stopAndDelete()
    }

    // MARK: Push Notifications

    /// Registers for push notifications once the inbox is in a ready state.
    /// If already in ready state, registration happens immediately.
    /// If not ready, waits for the ready state before registering.
    func registerForPushNotifications() async {
        await authorizationOperation.registerForPushNotifications()
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
        MyProfileRepository(inboxStateManager: inboxStateManager, databaseReader: databaseReader)
    }

    func myProfileWriter() -> any MyProfileWriterProtocol {
        MyProfileWriter(inboxStateManager: inboxStateManager, databaseWriter: databaseWriter)
    }

    // MARK: New Conversation

    func draftConversationComposer() -> any DraftConversationComposerProtocol {
        let clientConversationId: String = DBConversation.generateDraftConversationId()
        let draftConversationWriter = DraftConversationWriter(
            inboxStateManager: inboxStateManager,
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
            inboxStateManager: inboxStateManager,
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
        OutgoingMessageWriter(inboxStateManager: inboxStateManager,
                              databaseWriter: databaseWriter,
                              conversationId: conversationId)
    }

    // MARK: - Group Management

    func groupMetadataWriter() -> any ConversationMetadataWriterProtocol {
        ConversationMetadataWriter(
            inboxStateManager: inboxStateManager,
            databaseWriter: databaseWriter
        )
    }

    func groupPermissionsRepository() -> any GroupPermissionsRepositoryProtocol {
        GroupPermissionsRepository(inboxStateManager: inboxStateManager,
                                   databaseReader: databaseReader)
    }

    func uploadImage(data: Data, filename: String) async throws -> String {
        let result = try await inboxStateManager.waitForInboxReadyResult()
        return try await result.apiClient.uploadAttachment(
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
        let result = try await inboxStateManager.waitForInboxReadyResult()
        return try await result.apiClient.uploadAttachmentAndExecute(
            data: data,
            filename: filename,
            afterUpload: afterUpload
        )
    }

    // MARK: - Public Unused Inbox Methods

    static func createUnusedInboxIfNeeded(
        databaseWriter: any DatabaseWriter,
        databaseReader: any DatabaseReader,
        environment: AppEnvironment
    ) {
        Task(priority: .background) {
            await UnusedInboxCache.shared.prepareUnusedInboxIfNeeded(
                databaseWriter: databaseWriter,
                databaseReader: databaseReader,
                environment: environment
            )
        }
    }
}
