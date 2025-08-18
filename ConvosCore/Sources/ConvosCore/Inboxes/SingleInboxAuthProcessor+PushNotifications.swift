import Combine
import Foundation

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
        return scheduleWork(timeout: timeout) { inboxReadyResult in
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
        guard let inviteData = payload.notificationData?.inviteData else {
            Logger.error("Missing invite data in notification payload")
            return
        }

        Logger.info("Processing invite join request: autoApprove=\(inviteData.autoApprove)")
        // try await processInviteJoinRequest(inviteData: inviteData, apiClient: apiClient)
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
