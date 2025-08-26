import Combine
import Foundation
import GRDB

public class CachedPushNotificationHandler {
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
    public func handlePushNotification(userInfo: [AnyHashable: Any]) async throws {
        Logger.info("🔍 Processing raw push notification")
        let payload = PushNotificationPayload(userInfo: userInfo)

        guard payload.isValid else {
            Logger.error("Invalid push notification payload: \(payload)")
            return
        }

        guard let inboxId = payload.inboxId else {
            Logger.error("Push notification missing inboxId")
            return
        }

        Logger.info("Processing push notification for inbox: \(inboxId), type: \(payload.notificationType?.displayName ?? "unknown")")
        Logger.info("🔍 PARSED PAYLOAD: notificationType=\(payload.notificationType?.rawValue ?? "nil"), hasNotificationData=\(payload.notificationData != nil)")

        // Store the payload for NSE to retrieve after processing
        processedPayload = payload

        // Get or create messaging service for this inbox
        let messagingService = getOrCreateMessagingService(for: inboxId)
        try await messagingService.processPushNotification(payload: payload)
    }

    /// Gets the processed payload with decoded content for NSE use
    public func getProcessedPayload() -> PushNotificationPayload? {
        return processedPayload
    }

    /// Cleans up all resources
    public func cleanup() {
        Logger.info("Starting cleanup of \(messagingServices.count) messaging services")
        messagingServices.removeAll()
        processedPayload = nil // Clear processed payload
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
