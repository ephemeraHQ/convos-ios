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
        Logger.info("processPushNotification called for type: \(payload.notificationType?.rawValue ?? "nil")")
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

        Logger.debug("Processing notification type: \(payload.notificationType?.rawValue ?? "nil")")
        Logger.debug("Payload notification data: \(payload.notificationData != nil ? "present" : "nil")")

        switch payload.notificationType {
        case .protocolMessage:
            return try await handleProtocolMessage(
                payload: payload,
                client: client,
                apiClient: apiClient
            )
        case .inviteJoinRequest:
            return try await handleInviteJoinRequest(
                payload: payload,
                client: client,
                apiClient: apiClient
            )
        case .none:
            Logger.warning("Unknown notification type for payload: \(payload)")
            return nil
        }
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
           let contentTopic = protocolData.contentTopic,
           let currentInboxId = payload.inboxId else {
            Logger.error("Invalid protocolData in notification payload")
            return nil
        }

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

        let messageWriter = IncomingMessageWriter(databaseWriter: databaseWriter)
        let conversationWriter = ConversationWriter(databaseWriter: databaseWriter, messageWriter: messageWriter)
        let dbConversation = try await conversationWriter.store(conversation: conversation)
        try await messageWriter.store(message: decodedMessage, for: dbConversation)

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

    /// Handles invite join request notifications
    private func handleInviteJoinRequest(
        payload: PushNotificationPayload,
        client: any XMTPClientProvider,
        apiClient: any ConvosAPIClientProtocol
    ) async throws -> DecodedNotificationContent? {
        Logger.info("handleInviteJoinRequest called")

        guard let inviteData = payload.notificationData?.inviteData else {
            Logger.error("Missing invite data in notification payload")
            return nil
        }

        Logger.info("Processing invite join request: autoApprove=\(inviteData.autoApprove)")
        return try await processInviteJoinRequest(
            inviteData: inviteData,
            payload: payload,
            client: client,
            apiClient: apiClient
        )
    }

    /// Processes an invite join request from push notification
    /// - Parameters:
    ///   - inviteData: The invite join request data from the push notification
    ///   - payload: The push notification payload
    ///   - client: The XMTP client
    ///   - apiClient: The API client
    private func processInviteJoinRequest(
        inviteData: InviteJoinRequestData,
        payload: PushNotificationPayload,
        client: any XMTPClientProvider,
        apiClient: any ConvosAPIClientProtocol
    ) async throws -> DecodedNotificationContent? {
        guard let requesterInboxId = inviteData.requester?.xmtpId else {
            Logger.error("Missing requester inbox ID in invite data")
            return nil
        }

        Logger.info("Processing invite join request for group: \(inviteData.inviteCode?.groupId ?? "unknown"), requester: \(requesterInboxId)")

        // Check if auto-approve is enabled
        if !inviteData.autoApprove {
            Logger.info("Auto-approve is disabled, skipping automatic processing")
            // In a real implementation, you might want to store this request for manual approval
            return nil
        }

        // Get the group ID from the invite code data
        guard let groupId = inviteData.inviteCode?.groupId else {
            Logger.error("Missing group ID in invite code data")
            return nil
        }

        // Find the conversation using the group ID directly
        let xmtpConversation = try await client.conversationsProvider.findConversation(
            conversationId: groupId
        )
        guard let xmtpConversation else {
            Logger.error("Could not find conversation for group ID: \(groupId)")
            return nil
        }

        // Only process group conversations
        guard case .group(let group) = xmtpConversation else {
            Logger.warning("Expected Group but found DM, ignoring invite join request...")
            return nil
        }

        do {
            // Check if the requester is already a member
            let currentMembers = try await xmtpConversation.members()
            let memberInboxIds = currentMembers.map { $0.inboxId }

            if memberInboxIds.contains(requesterInboxId) {
                Logger.info("User \(requesterInboxId) is already a member of group \(group.id)")
                return nil
            }

            // Add the requester to the group
            Logger.info("Adding \(requesterInboxId) to group \(group.id)...")
            _ = try await group.addMembers(inboxIds: [requesterInboxId])

            // Delete the request from the backend (cleanup after successful processing)
            if let requestId = inviteData.requestId, !requestId.isEmpty {
                do {
                    Logger.info("Deleting processed join request: \(requestId)")
                    _ = try await apiClient.deleteRequestToJoin(requestId)
                    Logger.info("Successfully deleted join request: \(requestId)")
                } catch {
                    Logger.error("Failed to delete join request \(requestId): \(error.localizedDescription)")
                    // Don't throw here - the member was successfully added, deletion is cleanup
                }
            } else {
                Logger.warning("No request ID provided in invite data, skipping backend cleanup")
            }

            // Store the updated conversation
            Logger.info("Storing updated conversation with id: \(xmtpConversation.id)")
            let messageWriter = IncomingMessageWriter(databaseWriter: databaseWriter)
            let conversationWriter = ConversationWriter(databaseWriter: databaseWriter, messageWriter: messageWriter)
            let dBConversation = try await conversationWriter.store(conversation: xmtpConversation)

            Logger.info("Successfully processed invite join request for \(requesterInboxId)")

            let conversationName = dBConversation.name ?? ""
            let title = conversationName.isEmpty ? "Untitled" : conversationName
            return .init(
                title: title,
                body: "Someone accepted your invite",
                conversationId: groupId,
                userInfo: payload.userInfo
            )
        } catch {
            Logger.error("Failed to add member to group: \(error.localizedDescription)")
            throw error
        }
    }
}
