import Combine
import Foundation
import GRDB
import XMTPiOS

/// Extension providing push notification specific functionality for SingleInboxAuthProcessor
extension MessagingService {
    /// Processes a push notification when the inbox is ready
    /// - Parameters:
    ///   - payload: The decoded push notification payload
    func processPushNotification(
        payload: PushNotificationPayload
    ) async throws -> DecodedNotificationContent? {
        Logger.info("processPushNotification called")
        let inboxReadyResult = try await inboxStateManager.waitForInboxReadyResult()
        return try await self.handlePushNotification(
            inboxReadyResult: inboxReadyResult,
            payload: payload
        )
    }

    /// Handles the actual push notification processing when inbox is ready
    /// - Parameters:
    ///   - inboxReadyResult: The ready inbox with client and API client
    ///   - payload: The decoded push notification payload
    private func handlePushNotification(
        inboxReadyResult: InboxReadyResult,
        payload: PushNotificationPayload
    ) async throws -> DecodedNotificationContent? {
        let client = inboxReadyResult.client
        let apiClient = inboxReadyResult.apiClient

        // If the payload contains an apiJWT token, use it as override for this NSE process
        if let apiJWT = payload.apiJWT {
            Logger.info("Using apiJWT from notification payload")
            apiClient.overrideJWTToken(apiJWT)
        } else {
            Logger.warning("No apiJWT in payload, might not be able to use the Convos API")
        }

        Logger.debug("Payload notification data: \(payload.notificationData != nil ? "present" : "nil")")

        return try await handleProtocolMessage(
            payload: payload,
            client: client,
            apiClient: apiClient
        )
    }

    /// Handles protocol message notifications
    private func handleProtocolMessage(
        payload: PushNotificationPayload,
        client: any XMTPClientProvider,
        apiClient: any ConvosAPIClientProtocol
    ) async throws -> DecodedNotificationContent? {
        guard let protocolData = payload.notificationData?.protocolData else {
            Logger.error("Missing protocol data in notification payload")
            return nil
        }

        guard let contentTopic = protocolData.contentTopic else {
            Logger.error("Missing contentTopic in notification payload")
            return nil
        }

        // Welcome messages don't include encrypted content (too large for push)
        let isWelcomeTopic = contentTopic.contains("/w-")

        if protocolData.encryptedMessage == nil {
            // No encrypted content - must be a welcome message
            guard isWelcomeTopic else {
                Logger.error("Missing encryptedMessage for non-welcome topic: \(contentTopic)")
                return nil
            }

            Logger.info("Handling welcome message notification (no encrypted content)")
            return try await handleWelcomeMessage(
                contentTopic: contentTopic,
                client: client,
                userInfo: payload.userInfo
            )
        }

        // Regular message - decrypt the encrypted content
        guard let encryptedMessage = protocolData.encryptedMessage else {
            Logger.error("Missing encryptedMessage after nil check")
            return nil
        }

        let currentInboxId = client.inboxId

        // Try to decode the text message for notification display
        return try await decodeTextMessageWithSender(
            encryptedMessage: encryptedMessage,
            contentTopic: contentTopic,
            currentInboxId: currentInboxId,
            userInfo: payload.userInfo,
            client: client
        )
    }

    /// Handles welcome message notifications by syncing from network
    /// Welcome messages are too large for push notifications, so we sync from XMTP network
    /// Welcome messages indicate a new DM conversation with a join request
    private func handleWelcomeMessage(
        contentTopic: String,
        client: any XMTPClientProvider,
        userInfo: [AnyHashable: Any]
    ) async throws -> DecodedNotificationContent? {
        Logger.info("Syncing conversations from network for welcome message (DM with join request)")

        // Use the shared InviteJoinRequestsManager to handle the full flow (including adding to group)
        let joinRequestsManager = InviteJoinRequestsManager(
            identityStore: identityStore,
            databaseReader: databaseReader
        )

        let results = await joinRequestsManager.syncAndProcessJoinRequests(client: client)

        // Store all group conversations to ensure XMTP has complete group state
        for result in results {
            if let conversation = try await client.conversationsProvider.findConversation(conversationId: result.conversationId) {
                try await storeConversation(conversation)
            } else {
                Logger.error("Group conversation \(result.conversationId) not found after join")
            }
        }

        guard let firstResult = results.first else {
            Logger.warning("No valid join request found in DM messages after welcome message sync")
            return .droppedMessage
        }

        Logger.info("Successfully processed \(results.count) join request(s) from welcome message")

        return .init(
            title: firstResult.conversationName,
            body: "Someone accepted your invite 👀",
            conversationId: firstResult.conversationId,
            userInfo: userInfo
        )
    }

    /// Decodes a text message for notification display with sender info
    private func decodeTextMessageWithSender(
        encryptedMessage: String,
        contentTopic: String,
        currentInboxId: String,
        userInfo: [AnyHashable: Any],
        client: any XMTPClientProvider
    ) async throws -> DecodedNotificationContent? {
        // Extract conversation ID from topic path
        guard let conversationId = contentTopic.conversationIdFromXMTPGroupTopic else {
            Logger.warning("Unable to extract conversation id from contentTopic: \(contentTopic)")
            return nil
        }

        // Find the conversation
        guard let conversation = try await client.conversationsProvider.findConversation(conversationId: conversationId) else {
            Logger.warning("Conversation not found for topic: \(contentTopic), extracted ID: \(conversationId)")
            return nil
        }

        // Decode the encrypted message
        guard let messageBytes = Data(base64Encoded: Data(encryptedMessage.utf8)) else {
            Logger.warning("Failed to decode base64 encrypted message")
            return nil
        }

        // Process the message
        guard let decodedMessage = try await conversation.processMessage(messageBytes: messageBytes) else {
            Logger.warning("Failed to process message bytes")
            return nil
        }

        // Check if message is from self - if so, drop it
        if decodedMessage.senderInboxId == currentInboxId {
            Logger.info("Dropping notification - message from self")
            return .droppedMessage
        }

        switch conversation {
        case .dm:
            // DMs are only used for join requests (invite acceptance flow)
            // When someone accepts an invite, they send the signed invite back via DM
            // This allows us to add them to the group conversation they were invited to
            let joinRequestsManager = InviteJoinRequestsManager(
                identityStore: identityStore,
                databaseReader: databaseReader
            )

            do {
                if let result = try await joinRequestsManager.processJoinRequest(message: decodedMessage, client: client) {
                    // Valid join request - show notification
                    return .init(
                        title: result.conversationName,
                        body: "Someone accepted your invite 👀",
                        conversationId: result.conversationId,
                        userInfo: userInfo
                    )
                }
            } catch {
                // Not a valid join request - block the DM to prevent spam
                Logger.warning("DM is not a valid join request, blocking conversation")
                try? await conversation.updateConsentState(state: .denied)
                return .droppedMessage
            }

            // Shouldn't reach here, but if we do, drop the notification
            return .droppedMessage
        case .group:
            let dbConversation = try await storeConversation(conversation)
            let messageWriter = IncomingMessageWriter(databaseWriter: databaseWriter)
            _ = try await messageWriter.store(message: decodedMessage, for: dbConversation)

            // Check if the user was removed from the conversation
            let wasRemovedFromConversation = decodedMessage.update?.removedInboxIds.contains(currentInboxId) ?? false
            if wasRemovedFromConversation {
                Logger.info("Removed from conversation, dropping notification")
                return .droppedMessage
            }

            // Only handle text content type
            let encodedContentType = try decodedMessage.encodedContent.type
            guard encodedContentType == ContentTypeText else {
                Logger.info("Skipping non-text content type: \(encodedContentType.description)")
                return .droppedMessage
            }

            // Extract text content
            let content = try decodedMessage.content() as Any
            guard let textContent = content as? String else {
                Logger.warning("Could not extract text content from message")
                return nil
            }

            let notificationTitle: String?
            let notificationBody = textContent // Just the decoded text

            switch conversation {
            case .group(let group):
                notificationTitle = try group.name()
            case .dm:
                notificationTitle = nil
            }

            return .init(
                title: notificationTitle,
                body: notificationBody,
                conversationId: conversationId,
                userInfo: userInfo
            )
        }
    }

    /// Stores a conversation in the database along with its latest messages
    /// This ensures XMTP has complete group state for decrypting subsequent messages
    /// - Parameter conversation: The XMTP conversation to store
    /// - Returns: The stored database conversation
    @discardableResult
    private func storeConversation(_ conversation: XMTPiOS.Conversation) async throws -> DBConversation {
        let messageWriter = IncomingMessageWriter(databaseWriter: databaseWriter)
        let conversationWriter = ConversationWriter(
            identityStore: identityStore,
            databaseWriter: databaseWriter,
            messageWriter: messageWriter
        )
        return try await conversationWriter.storeWithLatestMessages(conversation: conversation)
    }
}
