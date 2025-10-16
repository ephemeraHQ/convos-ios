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

        guard let encryptedMessage = protocolData.encryptedMessage,
           let contentTopic = protocolData.contentTopic else {
            Logger.error("Invalid protocolData in notification payload")
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
            // handle all dms as join requests
            let joinRequestsManager = InviteJoinRequestsManager(
                identityStore: identityStore,
                databaseReader: databaseReader
            )
            guard let conversationId = try await joinRequestsManager.processJoinRequest(message: decodedMessage, client: client) else {
                Logger.warning("Failed processing join request")
                return .droppedMessage
            }

            return .init(
                title: "Untitled",
                body: "Someone accepted your invite",
                conversationId: conversationId,
                userInfo: userInfo
            )
        case .group:
            let messageWriter = IncomingMessageWriter(databaseWriter: databaseWriter)
            let conversationWriter = ConversationWriter(
                identityStore: identityStore,
                databaseWriter: databaseWriter,
                messageWriter: messageWriter
            )
            let dbConversation = try await conversationWriter.store(conversation: conversation)
            _ = try await messageWriter.store(message: decodedMessage, for: dbConversation)

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
}
