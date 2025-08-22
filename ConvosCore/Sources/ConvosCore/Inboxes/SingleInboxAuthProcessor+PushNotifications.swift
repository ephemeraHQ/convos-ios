import Combine
import Foundation
import GRDB
import XMTPiOS

/// Error types for notification processing
public enum NotificationError: Error {
    case messageShouldBeDropped
}

/// Extension providing push notification specific functionality for SingleInboxAuthProcessor
public extension SingleInboxAuthProcessor {
    /// Processes a push notification by scheduling work when the inbox is ready
    /// - Parameters:
    ///   - payload: The decoded push notification payload
    ///   - timeout: Timeout duration for inbox authorization (default: 30 seconds)
    /// - Returns: A publisher that emits when processing is complete
    func processPushNotification(
        payload: PushNotificationPayload,
        timeout: TimeInterval = 30
    ) -> AnyPublisher<Void, Error> {
        Logger.info("🚀 SingleInboxAuthProcessor: processPushNotification called for type: \(payload.notificationType?.rawValue ?? "nil")")
        return scheduleWork(timeout: timeout) { [weak self] inboxReadyResult in
            guard let self = self else {
                throw SingleInboxAuthProcessorError.processorDeallocated
            }
            Logger.info("🎯 SingleInboxAuthProcessor: Inbox ready, calling handlePushNotification")
            try await self.handlePushNotification(
                inboxReadyResult: inboxReadyResult,
                payload: payload
            )
        }
    }

    /// Processes a push notification using raw userInfo dictionary
    /// - Parameters:
    ///   - userInfo: The raw notification userInfo dictionary
    ///   - timeout: Timeout duration for inbox authorization (default: 30 seconds)
    /// - Returns: A publisher that emits when processing is complete
    func processPushNotification(
        userInfo: [AnyHashable: Any],
        timeout: TimeInterval = 30
    ) -> AnyPublisher<Void, Error> {
        let payload = PushNotificationPayload(userInfo: userInfo)
        return processPushNotification(payload: payload, timeout: timeout)
    }

    /// Handles the actual push notification processing when inbox is ready
    /// - Parameters:
    ///   - inboxReadyResult: The ready inbox with client and API client
    ///   - payload: The decoded push notification payload
    private func handlePushNotification(
        inboxReadyResult: InboxReadyResult,
        payload: PushNotificationPayload
    ) async throws {
        let client = inboxReadyResult.client
        let apiClient = inboxReadyResult.apiClient

        Logger.info("🔍 DEBUG: Processing notification type: \(payload.notificationType?.rawValue ?? "nil")")
        Logger.info("🔍 DEBUG: Payload notification data: \(payload.notificationData != nil ? "present" : "nil")")

        switch payload.notificationType {
        case .protocolMessage:
            try await handleProtocolMessage(
                payload: payload,
                client: client,
                apiClient: apiClient
            )
        case .inviteJoinRequest:
            try await handleInviteJoinRequest(
                payload: payload,
                client: client,
                apiClient: apiClient
            )
        case .none:
            Logger.warning("Unknown notification type for payload: \(payload)")
        }
    }

    /// Handles protocol message notifications
    private func handleProtocolMessage(
        payload: PushNotificationPayload,
        client: any XMTPClientProvider,
        apiClient: any ConvosAPIClientProtocol
    ) async throws {
        guard let protocolData = payload.notificationData?.protocolData else {
            Logger.error("Missing protocol data in notification payload")
            return
        }

        // NSE should ONLY decode for display, not sync
        // If we're in notification service extension and have encrypted message data, try to decode it
        if isNotificationServiceExtension,
           let encryptedMessage = protocolData.encryptedMessage,
           let contentTopic = protocolData.contentTopic,
           let currentInboxId = payload.inboxId {
            do {
                // Try to decode the text message for notification display
                if let result = try await decodeTextMessageWithSender(
                    encryptedMessage: encryptedMessage,
                    contentTopic: contentTopic,
                    currentInboxId: currentInboxId,
                    client: client
                ) {
                    Logger.info("Successfully decoded text message for notification: \(result.text)")

                    // Set decoded content directly on the payload object
                    try await setDecodedContentOnPayload(
                        payload: payload,
                        conversationId: protocolData.conversationId ?? contentTopic,
                        textContent: result.text,
                        senderInboxId: result.senderInboxId,
                        client: client
                    )
                } else {
                    Logger.info("Message was dropped (from self or non-text)")

                    // Throw an error to indicate this notification should be dropped
                    throw NotificationError.messageShouldBeDropped
                }
            } catch NotificationError.messageShouldBeDropped {
                // Re-throw to indicate notification should be dropped
                throw NotificationError.messageShouldBeDropped
            } catch {
                Logger.error("Failed to decode message in notification service: \(error)")
                // Don't throw here - show generic notification on decode error
            }

            // NSE should exit here - it only decodes for display, not sync
            Logger.info("NSE: Finished decoding for display, skipping sync")
            return
        } else if !isNotificationServiceExtension, let contentTopic = protocolData.contentTopic {
            // For main app, just sync the conversation
            Logger.info("Processing protocol message for topic: \(contentTopic)")
            try await syncConversationIfNeeded(contentTopic: contentTopic, client: client)
        }
    }

    /// Result type for decoded text message with sender info
    private struct DecodedMessageResult {
        let text: String
        let senderInboxId: String
    }

    /// Decodes a text message for notification display with sender info
    private func decodeTextMessageWithSender(
        encryptedMessage: String,
        contentTopic: String,
        currentInboxId: String,
        client: any XMTPClientProvider
    ) async throws -> DecodedMessageResult? {
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
            return nil
        }

        // Only handle text content type
        let encodedContentType = try decodedMessage.encodedContent.type
        guard encodedContentType == ContentTypeText else {
            Logger.info("Skipping non-text content type: \(encodedContentType.description)")
            return nil
        }

        // Extract text content
        let content = try decodedMessage.content() as Any
        guard let textContent = content as? String else {
            Logger.warning("Could not extract text content from message")
            return nil
        }

        return DecodedMessageResult(text: textContent, senderInboxId: decodedMessage.senderInboxId)
    }

    /// Sets decoded content directly on the payload object for NSE access
    private func setDecodedContentOnPayload(
        payload: PushNotificationPayload,
        conversationId: String,
        textContent: String,
        senderInboxId: String,
        client: any XMTPClientProvider
    ) async throws {
        var notificationTitle: String?
        let notificationBody = textContent // Just the decoded text

        // Try to get group name from the conversation we already found during decoding
        // This should be safe since we already accessed this conversation successfully
        do {
            if let conversation = try await client.conversationsProvider.findConversation(conversationId: conversationId) {
                if case .group(let group) = conversation {
                    // Get group name from XMTP group
                    let groupName = try group.name()
                    if !groupName.isEmpty {
                        notificationTitle = groupName
                        Logger.info("Found group name for notification: \(groupName)")
                    } else {
                        Logger.info("Group has empty name, using default title")
                    }
                } else {
                    Logger.info("Conversation is DM, using default title")
                }
            } else {
                Logger.warning("Could not find conversation again for notification")
            }
        } catch {
            Logger.warning("Error getting group name for notification: \(error)")
            // Continue with no custom title
        }

        // Set decoded content directly on the payload object
        payload.decodedTitle = notificationTitle
        payload.decodedBody = notificationBody

        Logger.info("Set decoded content on payload - Title: \(notificationTitle ?? "default"), Body: \(notificationBody)")
    }

    /// Syncs a conversation if needed when a notification is received
    private func syncConversationIfNeeded(
        contentTopic: String,
        client: any XMTPClientProvider
    ) async throws {
        // Extract conversation ID from topic path
        guard let conversationId = contentTopic.conversationIdFromXMTPGroupTopic else {
            Logger.warning("Unable to extract conversation ID from topic: \(contentTopic)")
            return
        }

        // Find and sync the conversation using the correct method
        if let conversation = try await client.conversationsProvider.findConversation(conversationId: conversationId) {
            try await conversation.sync()
            Logger.info("Synced conversation for topic: \(contentTopic)")
        }
    }

    /// Handles invite join request notifications
    private func handleInviteJoinRequest(
        payload: PushNotificationPayload,
        client: any XMTPClientProvider,
        apiClient: any ConvosAPIClientProtocol
    ) async throws {
        Logger.info("🎯 INVITE JOIN REQUEST: handleInviteJoinRequest called!")

        guard let inviteData = payload.notificationData?.inviteData else {
            Logger.error("Missing invite data in notification payload")
            return
        }

        Logger.info("Processing invite join request: autoApprove=\(inviteData.autoApprove)")
        try await processInviteJoinRequest(inviteData: inviteData, payload: payload, client: client, apiClient: apiClient)
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
    ) async throws {
        guard let requesterInboxId = inviteData.requester?.xmtpId else {
            Logger.error("Missing requester inbox ID in invite data")
            return
        }

        Logger.info("Processing invite join request for group: \(inviteData.inviteCode?.groupId ?? "unknown"), requester: \(requesterInboxId)")

        // Check if auto-approve is enabled
        if !inviteData.autoApprove {
            Logger.info("Auto-approve is disabled, skipping automatic processing")
            // In a real implementation, you might want to store this request for manual approval
            return
        }

        // Get the group ID from the invite code data
        guard let groupId = inviteData.inviteCode?.groupId else {
            Logger.error("Missing group ID in invite code data")
            return
        }

        // Find the conversation using the group ID directly
        guard let xmtpConversation = try await client.conversationsProvider.findConversation(conversationId: groupId) else {
            Logger.error("Could not find conversation for group ID: \(groupId)")
            return
        }

        // Only process group conversations
        guard case .group(let group) = xmtpConversation else {
            Logger.warning("Expected Group but found DM, ignoring invite join request...")
            return
        }

        do {
            // Check if the requester is already a member
            let currentMembers = try await xmtpConversation.members()
            let memberInboxIds = currentMembers.map { $0.inboxId }

            if memberInboxIds.contains(requesterInboxId) {
                Logger.info("User \(requesterInboxId) is already a member of group \(group.id)")
                return
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
            _ = try await conversationWriter.store(conversation: xmtpConversation)

            Logger.info("Successfully processed invite join request for \(requesterInboxId)")
        } catch {
            Logger.error("Failed to add member to group: \(error.localizedDescription)")
            throw error
        }
    }

    /// Decodes and stores an XMTP message from push notification data
    /// - Parameters:
    ///   - contentTopic: The XMTP content topic
    ///   - client: The XMTP client
    private func decodeAndStoreMessage(
        contentTopic: String,
        client: any XMTPClientProvider
    ) async throws {
        // Implementation would decode the message and store it in the database
        // This is a placeholder for the actual implementation
        Logger.info("Processing XMTP message for topic: \(contentTopic)")
    }

    /// Processes invite join request data
    /// - Parameters:
    ///   - inviteData: The invite join request data
    ///   - apiClient: The API client
    private func processInviteJoinRequest(
        inviteData: InviteJoinRequestData,
        apiClient: any ConvosAPIClientProtocol
    ) async throws {
        // Implementation would process the invite join request
        // This is a placeholder for the actual implementation
        Logger.info("Processing invite join request: \(inviteData)")
    }
}
