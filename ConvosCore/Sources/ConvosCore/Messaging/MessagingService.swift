import Combine
import Foundation
import GRDB
import XMTPiOS

final class MessagingService: MessagingServiceProtocol {
    private let authorizationOperation: any AuthorizeInboxOperationProtocol
    internal let inboxStateManager: any InboxStateManagerProtocol
    private let databaseReader: any DatabaseReader
    internal let identityStore: any KeychainIdentityStoreProtocol
    internal let databaseWriter: any DatabaseWriter
    private var cancellables: Set<AnyCancellable> = []

    static func authorizedMessagingService(
        databaseWriter: any DatabaseWriter,
        databaseReader: any DatabaseReader,
        environment: AppEnvironment,
        startsStreamingServices: Bool,
        registersForPushNotifications: Bool = true
    ) -> MessagingService {
        let identityStore = environment.defaultIdentityStore
        let authorizationOperation = AuthorizeInboxOperation.authorize(
            identityStore: identityStore,
            databaseReader: databaseReader,
            databaseWriter: databaseWriter,
            environment: environment,
            startsStreamingServices: startsStreamingServices,
            registersForPushNotifications: registersForPushNotifications
        )
        return .init(
            authorizationOperation: authorizationOperation,
            databaseWriter: databaseWriter,
            databaseReader: databaseReader,
            identityStore: identityStore
        )
    }

    internal init(authorizationOperation: AuthorizeInboxOperation,
                  databaseWriter: any DatabaseWriter,
                  databaseReader: any DatabaseReader,
                  identityStore: any KeychainIdentityStoreProtocol) {
        self.identityStore = identityStore
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

    func reset() async {
        await authorizationOperation.reset()
    }

    // MARK: Push Notifications

    /// Registers for push notifications once the inbox is in a ready state.
    /// If already in ready state, registration happens immediately.
    /// If not ready, waits for the ready state before registering.
    func registerForPushNotifications() async {
        await authorizationOperation.registerForPushNotifications()
    }

    // MARK: My Profile

    func myProfileWriter() -> any MyProfileWriterProtocol {
        MyProfileWriter(inboxStateManager: inboxStateManager, databaseWriter: databaseWriter)
    }

    // MARK: New Conversation

    func draftConversationComposer() -> any DraftConversationComposerProtocol {
        let draftConversationWriter = DraftConversationWriter(
            inboxStateManager: inboxStateManager,
            identityStore: identityStore,
            databaseReader: databaseReader,
            databaseWriter: databaseWriter,
        )
        return DraftConversationComposer(
            myProfileWriter: myProfileWriter(),
            draftConversationWriter: draftConversationWriter,
            draftConversationRepository: DraftConversationRepository(
                dbReader: databaseReader,
                writer: draftConversationWriter,
                inboxStateManager: inboxStateManager
            ),
            conversationConsentWriter: conversationConsentWriter(),
            conversationLocalStateWriter: conversationLocalStateWriter(),
            conversationMetadataWriter: conversationMetadataWriter()
        )
    }

    // MARK: Conversations

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

    func messageWriter(for conversationId: String) -> any OutgoingMessageWriterProtocol {
        OutgoingMessageWriter(inboxStateManager: inboxStateManager,
                              databaseWriter: databaseWriter,
                              conversationId: conversationId)
    }

    // MARK: - Group Management

    func conversationMetadataWriter() -> any ConversationMetadataWriterProtocol {
        ConversationMetadataWriter(
            inboxStateManager: inboxStateManager,
            databaseWriter: databaseWriter
        )
    }

    func conversationPermissionsRepository() -> any ConversationPermissionsRepositoryProtocol {
        ConversationPermissionsRepository(inboxStateManager: inboxStateManager,
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
}
