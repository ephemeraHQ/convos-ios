import Combine
import Foundation
import GRDB

public actor CachedPushNotificationHandler {
    private var messagingServices: [String: MessagingService] = [:]

    // Store the processed payload for NSE access
    private var processedPayload: PushNotificationPayload?

    private let databaseReader: any DatabaseReader
    private let databaseWriter: any DatabaseWriter
    private let environment: AppEnvironment

    public init(
        databaseReader: any DatabaseReader,
        databaseWriter: any DatabaseWriter,
        environment: AppEnvironment,
    ) {
        self.databaseReader = databaseReader
        self.databaseWriter = databaseWriter
        self.environment = environment
    }

    /// Handles a push notification using the structured payload
    /// - Parameter userInfo: The raw notification userInfo dictionary
    public func handlePushNotification(payload: PushNotificationPayload) async throws -> DecodedNotificationContent? {
        Logger.info("Processing raw push notification")

        guard payload.isValid else {
            Logger.error("Invalid push notification payload: \(payload)")
            return nil
        }

        guard let inboxId = payload.inboxId else {
            Logger.error("Push notification missing inboxId")
            return nil
        }

        Logger.info("Processing push notification for inbox: \(inboxId), type: \(payload.notificationType?.displayName ?? "unknown")")
        Logger.info("PARSED PAYLOAD: notificationType=\(payload.notificationType?.rawValue ?? "nil"), hasNotificationData=\(payload.notificationData != nil)")

        // Get or create messaging service for this inbox
        let messagingService = getOrCreateMessagingService(for: inboxId)
        return try await messagingService.processPushNotification(payload: payload)
    }

    /// Cleans up all resources
    public func cleanup() {
        Logger.info("Starting cleanup of \(messagingServices.count) messaging services")
        messagingServices.removeAll()
    }

    // MARK: - Private Methods

    private func getOrCreateMessagingService(for inboxId: String) -> MessagingService {
        if let existing = messagingServices[inboxId] {
            return existing
        }

        let messagingService = MessagingService.authorizedMessagingService(
            for: inboxId,
            databaseWriter: databaseWriter,
            databaseReader: databaseReader,
            environment: environment,
            startsStreamingServices: false,
            registersForPushNotifications: false
        )
        messagingServices[inboxId] = messagingService
        return messagingService
    }
}
