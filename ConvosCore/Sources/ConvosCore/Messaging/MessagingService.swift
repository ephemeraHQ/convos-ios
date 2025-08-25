import Combine
import Foundation
import GRDB
import XMTPiOS

final class MessagingService: MessagingServiceProtocol {
    // MARK: - Unused Inbox Management

    private static let keychainService: KeychainService<UnusedInboxKeychainItem> = .init()
    private static var isCreatingUnusedInbox: Bool = false
    private static let unusedInboxQueue: DispatchQueue = DispatchQueue(label: "org.convos.unused-inbox-queue")
    private static var unusedMessagingService: MessagingService?
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
        registersForPushNotifications: Bool = true
    ) -> MessagingService {
        let authorizationOperation = AuthorizeInboxOperation.authorize(
            inboxId: inboxId,
            databaseReader: databaseReader,
            databaseWriter: databaseWriter,
            environment: environment,
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
    ) -> MessagingService {
        // Check if we have a pre-created unused messaging service
        if let unusedService = unusedMessagingService {
            Logger.info("Using pre-created unused messaging service")

            // Clear the static reference
            unusedMessagingService = nil

            // Clear the unused inbox from keychain
            clearUnusedInbox()

            // Schedule background task to create a new unused inbox
            scheduleUnusedInboxCreation(
                databaseWriter: databaseWriter,
                databaseReader: databaseReader,
                environment: environment
            )

            // Return the pre-created service
            return unusedService
        }

        // Check for an unused inbox ID in keychain (fallback)
        if let unusedInboxId = getUnusedInbox() {
            Logger.info("Using unused inbox ID from keychain: \(unusedInboxId)")

            // Clear the unused inbox from keychain
            clearUnusedInbox()

            // Schedule background task to create a new unused inbox
            scheduleUnusedInboxCreation(
                databaseWriter: databaseWriter,
                databaseReader: databaseReader,
                environment: environment
            )

            // Use the existing inbox with authorize
            let authorizationOperation = AuthorizeInboxOperation.authorize(
                inboxId: unusedInboxId,
                databaseReader: databaseReader,
                databaseWriter: databaseWriter,
                environment: environment,
                registersForPushNotifications: true
            )
            return .init(
                inboxId: unusedInboxId,
                authorizationOperation: authorizationOperation,
                databaseWriter: databaseWriter,
                databaseReader: databaseReader
            )
        }

        // No unused inbox available, create a new one
        Logger.info("No unused inbox available, creating new one")
        let authorizationOperation = AuthorizeInboxOperation.register(
            databaseReader: databaseReader,
            databaseWriter: databaseWriter,
            environment: environment,
            registersForPushNotifications: true
        )

        // Schedule background task to create an unused inbox for next time
        scheduleUnusedInboxCreation(
            databaseWriter: databaseWriter,
            databaseReader: databaseReader,
            environment: environment
        )

        return .init(
            inboxId: nil,
            authorizationOperation: authorizationOperation,
            databaseWriter: databaseWriter,
            databaseReader: databaseReader
        )
    }

    private init(inboxId: String?,
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

    func stopAndDelete() {
        authorizationOperation.stopAndDelete()
    }

    func stopAndDelete() async {
        await authorizationOperation.stopAndDelete()
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
        // Check if we already have an unused messaging service ready
        if unusedMessagingService != nil {
            Logger.debug("Unused messaging service already exists, skipping creation")
            return
        }

        // Check if we have an unused inbox ID in keychain
        if let unusedInboxId = getUnusedInbox() {
            Logger.info("Found unused inbox ID in keychain, authorizing it: \(unusedInboxId)")

            // Create and authorize the messaging service in background
            Task {
                let authorizationOperation = AuthorizeInboxOperation.authorize(
                    inboxId: unusedInboxId,
                    databaseReader: databaseReader,
                    databaseWriter: databaseWriter,
                    environment: environment,
                    registersForPushNotifications: false // Don't register for push for unused inbox
                )

                let messagingService = MessagingService(
                    inboxId: unusedInboxId,
                    authorizationOperation: authorizationOperation,
                    databaseWriter: databaseWriter,
                    databaseReader: databaseReader
                )

                do {
                    // Wait for it to be ready
                    _ = try await messagingService.inboxStateManager.waitForInboxReadyResult()

                    // Store it as the unused messaging service
                    unusedMessagingService = messagingService

                    Logger.info("Successfully authorized unused inbox from keychain: \(unusedInboxId)")
                } catch {
                    Logger.error("Failed to authorize unused inbox from keychain: \(error)")
                    // Clear the invalid inbox ID from keychain
                    clearUnusedInbox()
                    // Clean up the messaging service
                    await messagingService.authorizationOperation.stopAndDelete()

                    // Schedule creation of a new unused inbox
                    scheduleUnusedInboxCreation(
                        databaseWriter: databaseWriter,
                        databaseReader: databaseReader,
                        environment: environment
                    )
                }
            }
            return
        }

        // No unused inbox exists, schedule creation of a new one
        Logger.info("No unused inbox found, scheduling creation on app startup")
        scheduleUnusedInboxCreation(
            databaseWriter: databaseWriter,
            databaseReader: databaseReader,
            environment: environment
        )
    }

    // MARK: - Private Unused Inbox Methods

    private static func getUnusedInbox() -> String? {
        do {
            return try keychainService.retrieveString(UnusedInboxKeychainItem())
        } catch {
            Logger.debug("No unused inbox found in keychain: \(error)")
            return nil
        }
    }

    private static func saveUnusedInbox(_ inboxId: String) {
        do {
            try keychainService.saveString(inboxId, for: UnusedInboxKeychainItem())
            Logger.info("Saved unused inbox to keychain: \(inboxId)")
        } catch {
            Logger.error("Failed to save unused inbox to keychain: \(error)")
        }
    }

    private static func clearUnusedInbox() {
        do {
            try keychainService.delete(UnusedInboxKeychainItem())
            Logger.debug("Cleared unused inbox from keychain")
        } catch {
            Logger.debug("Failed to clear unused inbox from keychain: \(error)")
        }
    }

    private static func scheduleUnusedInboxCreation(
        databaseWriter: any DatabaseWriter,
        databaseReader: any DatabaseReader,
        environment: AppEnvironment
    ) {
        unusedInboxQueue.async {
            guard !isCreatingUnusedInbox else {
                Logger.debug("Already creating unused inbox, skipping")
                return
            }

            isCreatingUnusedInbox = true

            Task {
                await createUnusedInbox(
                    databaseWriter: databaseWriter,
                    databaseReader: databaseReader,
                    environment: environment
                )

                await MainActor.run {
                    isCreatingUnusedInbox = false
                }
            }
        }
    }

    private static func createUnusedInbox(
        databaseWriter: any DatabaseWriter,
        databaseReader: any DatabaseReader,
        environment: AppEnvironment
    ) async {
        Logger.info("Creating new unused inbox in background")

        let authorizationOperation = AuthorizeInboxOperation.register(
            databaseReader: databaseReader,
            databaseWriter: databaseWriter,
            environment: environment,
            registersForPushNotifications: false // Don't register for push for unused inbox
        )

        let tempMessagingService = MessagingService(
            inboxId: nil,
            authorizationOperation: authorizationOperation,
            databaseWriter: databaseWriter,
            databaseReader: databaseReader
        )

        // Wait for the inbox to be ready
        do {
            let result = try await tempMessagingService.inboxStateManager.waitForInboxReadyResult()
            let inboxId = result.client.inboxId

            // Save the inbox ID to keychain
            saveUnusedInbox(inboxId)

            // Store the messaging service instance
            unusedMessagingService = tempMessagingService

            Logger.info("Successfully created unused inbox: \(inboxId)")
        } catch {
            Logger.error("Failed to create unused inbox: \(error)")
            // Clean up on error
            await tempMessagingService.authorizationOperation.stopAndDelete()
        }
    }
}
