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

    /// Handles invite join request notifications
    private func handleInviteJoinRequest(
        payload: PushNotificationPayload,
        client: any XMTPClientProvider,
        apiClient: any ConvosAPIClientProtocol
    ) async throws -> DecodedNotificationContent? {
        Logger.info("handleInviteJoinRequest called")

        guard let notificationData = payload.notificationData else {
            Logger.error("Missing notification data in payload")
            return nil
        }

        Logger.info("Notification data present: \(notificationData)")

        guard let inviteData = notificationData.inviteData else {
            Logger.error("Missing invite data in notification payload")
            return nil
        }

        Logger.info("Processing invite join request: autoApprove=\(inviteData.autoApprove)")
        Logger.info("Invite data: \(inviteData)")

        return try await processInviteJoinRequest(
            inviteData: inviteData,
            payload: payload,
            client: client,
            apiClient: apiClient
        )
    }

    /// Processes an invite join request from push notification
    ///
    /// Flow Strategy:
    /// 1. Accept backend request (creates InviteCodeUse)
    /// 2. Add user to XMTP group
    /// 3. Clean up processed request
    /// 4. Store updated conversation
    ///
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

            var backendAccepted = false

            if let requestId = inviteData.requestId, !requestId.isEmpty {
                do {
                    Logger.info("Accepting join request: \(requestId)")
                    let acceptResponse = try await apiClient.acceptRequestToJoin(requestId)

                    if acceptResponse.alreadyAccepted == true {
                        Logger.info("Request \(requestId) was already processed at \(acceptResponse.inviteCodeUse.usedAt)")
                    } else {
                        Logger.info("Request \(requestId) accepted, member added at \(acceptResponse.inviteCodeUse.usedAt)")
                    }

                    backendAccepted = true
                } catch {
                    // Handle errors with proper recovery logic
                    backendAccepted = try handleAcceptRequestError(error)
                }
            } else {
                Logger.error("No request ID provided - cannot ensure backend consistency")
                throw NSError(domain: "InviteJoinRequest", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Missing request ID - cannot process join request"
                ])
            }

            // Only add to XMTP if backend acceptance succeeded
            if backendAccepted {
                try await addMemberToXMTPGroup(
                    requesterInboxId: requesterInboxId,
                    group: group,
                    xmtpConversation: xmtpConversation
                )
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

    /// Adds a member to an XMTP group with membership verification
    /// - Parameters:
    ///   - requesterInboxId: The inbox ID of the user to add
    ///   - group: The XMTP group to add the user to
    ///   - xmtpConversation: The XMTP conversation for membership checks
    private func addMemberToXMTPGroup(
        requesterInboxId: String,
        group: XMTPiOS.Group,
        xmtpConversation: XMTPiOS.Conversation
    ) async throws {
        // Check if user is already a member (added by someone else or another process) before attempting to add
        let updatedMembers = try await xmtpConversation.members()
        let updatedMemberInboxIds = updatedMembers.map { $0.inboxId }

        if updatedMemberInboxIds.contains(requesterInboxId) {
            Logger.info("User \(requesterInboxId) was already added to group \(group.id) by another process")
        } else {
            Logger.info("Adding \(requesterInboxId) to XMTP group \(group.id)")
            do {
                _ = try await group.addMembers(inboxIds: [requesterInboxId])
                Logger.info("Successfully added \(requesterInboxId) to XMTP group")
            } catch {
                Logger.error("XMTP user addition failed")
                throw error
            }
        }
    }

    /// Handles errors from accept request API calls and determines if XMTP addition should proceed
    /// - Parameter error: The error from the accept request API call
    /// - Returns: true if XMTP addition should proceed despite the error, false otherwise
    /// - Throws: Rethrows the error if it's a fatal error that should stop processing
    private func handleAcceptRequestError(_ error: Error) throws -> Bool {
        if let apiError = error as? APIError {
            switch apiError {
            case .badRequest(let message):
                Logger.error("Request validation failed: \(message ?? "Unknown validation error")")
                throw error
            case .notFound:
                Logger.error("Request not found - likely expired or invalid")
                throw error
            case .forbidden:
                Logger.error("Permission denied for request acceptance")
                throw error
            case .serverError(let message):
                Logger.warning("Server error - this might be temporary, but proceeding with XMTP addition: \(message ?? "Unknown server error")")
                return true
            case .notAuthenticated:
                Logger.error("Authentication failed for request acceptance")
                throw error
            default:
                Logger.error("Unexpected API error: \(apiError)")
                throw error
            }
        } else {
            // Network or other errors - might be temporary, proceed with XMTP addition
            Logger.warning("Network/other error accepting request - proceeding with XMTP addition: \(error)")
            return true
        }
    }
}
