import Foundation
import GRDB
import XMTPiOS

// MARK: - Protocol

protocol StreamProcessorProtocol: Actor {
    func processConversation(
        _ conversation: XMTPiOS.Group,
        client: AnyClientProvider,
        apiClient: any ConvosAPIClientProtocol
    ) async throws

    func processConversation(
        _ conversation: any ConversationSender,
        client: AnyClientProvider,
        apiClient: any ConvosAPIClientProtocol
    ) async throws

    func processMessage(
        _ message: DecodedMessage,
        client: AnyClientProvider,
        apiClient: any ConvosAPIClientProtocol,
        activeConversationId: String?
    ) async
}

/// Processes conversations and messages from XMTP streams
///
/// StreamProcessor handles the processing of individual conversations and messages
/// received from XMTP streams. It coordinates:
/// - Validating conversation consent states
/// - Storing conversations and messages to the database
/// - Processing join requests from DMs
/// - Managing conversation permissions and metadata
/// - Subscribing to push notification topics
/// - Marking conversations as unread when appropriate
///
/// This processor is used by both SyncingManager (for continuous streaming) and
/// ConversationStateMachine (for processing newly created/joined conversations).
actor StreamProcessor: StreamProcessorProtocol {
    // MARK: - Properties

    private let identityStore: any KeychainIdentityStoreProtocol
    private let conversationWriter: any ConversationWriterProtocol
    private let messageWriter: any IncomingMessageWriterProtocol
    private let localStateWriter: any ConversationLocalStateWriterProtocol
    private let joinRequestsManager: any InviteJoinRequestsManagerProtocol
    private let consentStates: [ConsentState] = [.allowed, .unknown]

    // MARK: - Initialization

    init(
        identityStore: any KeychainIdentityStoreProtocol,
        databaseWriter: any DatabaseWriter,
        databaseReader: any DatabaseReader
    ) {
        self.identityStore = identityStore
        let messageWriter = IncomingMessageWriter(databaseWriter: databaseWriter)
        self.conversationWriter = ConversationWriter(
            identityStore: identityStore,
            databaseWriter: databaseWriter,
            messageWriter: messageWriter
        )
        self.messageWriter = messageWriter
        self.localStateWriter = ConversationLocalStateWriter(databaseWriter: databaseWriter)
        self.joinRequestsManager = InviteJoinRequestsManager(
            identityStore: identityStore,
            databaseReader: databaseReader
        )
    }

    // MARK: - Public Interface

    func processConversation(
        _ conversation: any ConversationSender,
        client: AnyClientProvider,
        apiClient: any ConvosAPIClientProtocol
    ) async throws {
        guard let group = conversation as? XMTPiOS.Group else {
            Logger.warning("Passed type other than Group")
            return
        }
        try await processConversation(group, client: client, apiClient: apiClient)
    }

    func processConversation(
        _ conversation: XMTPiOS.Group,
        client: AnyClientProvider,
        apiClient: any ConvosAPIClientProtocol
    ) async throws {
        guard try await shouldProcessConversation(conversation, client: client) else { return }

        let creatorInboxId = try await conversation.creatorInboxId()
        if creatorInboxId == client.inboxId {
            // we created the conversation, update permissions and set inviteTag
            try await conversation.ensureInviteTag()
            let permissions = try conversation.permissionPolicySet()
            if permissions.addMemberPolicy != .allow {
                // by default allow all members to invite others
                try await conversation.updateAddMemberPermission(newPermissionOption: .allow)
            }
        }

        Logger.info("Syncing conversation: \(conversation.id)")
        try await conversationWriter.storeWithLatestMessages(
            conversation: conversation,
            inboxId: client.inboxId
        )

        // Subscribe to push notifications
        await subscribeToConversationTopics(
            conversationId: conversation.id,
            client: client,
            apiClient: apiClient,
            context: "on stream"
        )
    }

    func processMessage(
        _ message: DecodedMessage,
        client: AnyClientProvider,
        apiClient: any ConvosAPIClientProtocol,
        activeConversationId: String?
    ) async {
        do {
            guard let conversation = try await client.conversationsProvider.findConversation(
                conversationId: message.conversationId
            ) else {
                Logger.error("Conversation not found for message")
                return
            }

            switch conversation {
            case .dm:
                do {
                    _ = try await joinRequestsManager.processJoinRequest(
                        message: message,
                        client: client
                    )
                    Logger.info("Processed potential join request: \(message.id)")
                } catch {
                    Logger.error("Failed processing join request: \(error)")
                }
            case .group(let conversation):
                do {
                    guard try await shouldProcessConversation(conversation, client: client) else {
                        Logger.warning("Received invalid group message, skipping...")
                        return
                    }

                    // Store conversation and message
                    let dbConversation = try await conversationWriter.store(
                        conversation: conversation,
                        inboxId: client.inboxId
                    )
                    let result = try await messageWriter.store(message: message, for: dbConversation)

                    // Mark unread if needed
                    if result.contentType.marksConversationAsUnread,
                       conversation.id != activeConversationId,
                       message.senderInboxId != client.inboxId {
                        try await localStateWriter.setUnread(true, for: conversation.id)
                    }

                    Logger.info("Processed message: \(message.id)")
                } catch {
                    Logger.error("Failed processing group message: \(error.localizedDescription)")
                }
            }
        } catch {
            Logger.warning("Stopped processing message from error: \(error.localizedDescription)")
        }
    }

    // MARK: - Private Helpers

    /// Checks if a conversation should be processed based on its consent state.
    /// If consent is unknown but there's an outgoing join request, updates consent to allowed.
    /// - Parameters:
    ///   - conversation: The conversation to check
    ///   - client: The client provider
    /// - Returns: True if the conversation has allowed consent and should be processed
    private func shouldProcessConversation(
        _ conversation: XMTPiOS.Group,
        client: AnyClientProvider
    ) async throws -> Bool {
        var consentState = try conversation.consentState()
        guard consentState != .allowed else {
            return true
        }

        guard try await conversation.creatorInboxId() != client.inboxId else {
            return true
        }

        if consentState == .unknown {
            let hasOutgoingJoinRequest = try await joinRequestsManager.hasOutgoingJoinRequest(
                for: conversation,
                client: client
            )

            if hasOutgoingJoinRequest {
                try await conversation.updateConsentState(state: .allowed)
                consentState = try conversation.consentState()
            }
        }

        return consentState == .allowed
    }

    // MARK: - Push Notifications

    private func subscribeToConversationTopics(
        conversationId: String,
        client: AnyClientProvider,
        apiClient: any ConvosAPIClientProtocol,
        context: String
    ) async {
        let conversationTopic = conversationId.xmtpGroupTopicFormat
        let welcomeTopic = client.installationId.xmtpWelcomeTopicFormat

        guard let identity = try? await identityStore.identity(for: client.inboxId) else {
            Logger.warning("Identity not found, skipping push notification subscription")
            return
        }

        do {
            let deviceId = DeviceInfo.deviceIdentifier
            try await apiClient.subscribeToTopics(
                deviceId: deviceId,
                clientId: identity.clientId,
                topics: [conversationTopic, welcomeTopic]
            )
            Logger.info("Subscribed to push topics \(context): \(conversationTopic), \(welcomeTopic)")
        } catch {
            Logger.error("Failed subscribing to topics \(context): \(error)")
        }
    }
}
