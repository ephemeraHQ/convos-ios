import Combine
import Foundation
import GRDB
import XMTPiOS

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
        return scheduleWork(timeout: timeout) { inboxReadyResult in
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

        if let contentTopic = protocolData.contentTopic {
            Logger.info("Processing protocol message for topic: \(contentTopic)")
            // try await decodeAndStoreMessage(contentTopic: contentTopic, client: client)
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
        guard let inviteCode = inviteData.inviteCode?.code else {
            Logger.error("Missing invite code in invite join request")
            return
        }

        guard let requesterInboxId = inviteData.requester?.xmtpId else {
            Logger.error("Missing requester inbox ID in invite data")
            return
        }

        Logger.info("Processing invite join request for code: \(inviteCode), group: \(inviteData.inviteCode?.groupId ?? "unknown"), requester: \(requesterInboxId)")

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

            // Store the updated conversation
            Logger.info("Storing updated conversation with id: \(xmtpConversation.id)")
            let messageWriter = IncomingMessageWriter(databaseWriter: databaseWriter)
            let conversationWriter = ConversationWriter(databaseWriter: databaseWriter, messageWriter: messageWriter)
            try await conversationWriter.store(conversation: xmtpConversation)

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
