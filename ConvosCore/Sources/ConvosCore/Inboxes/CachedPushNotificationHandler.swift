import Combine
import Foundation
import GRDB

// MARK: - Errors
public enum NotificationProcessingError: Error {
    case timeout
    case invalidPayload
}

public actor CachedPushNotificationHandler {
    private var messagingServices: [String: MessagingService] = [:] // Keyed by inboxId

    // Track last access time for cleanup (keyed by inboxId)
    private var lastAccessTime: [String: Date] = [:]

    // Maximum age for cached services (10 minutes)
    private let maxServiceAge: TimeInterval = 600

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

    /// Handles a push notification using the structured payload with timeout protection
    /// - Parameters:
    ///   - payload: The push notification payload to process
    ///   - timeout: Maximum time to process (default: 25 seconds for NSE's 30 second limit)
    /// - Returns: Decoded notification content if successful
    public func handlePushNotification(
        payload: PushNotificationPayload,
        timeout: TimeInterval = 25
    ) async throws -> DecodedNotificationContent? {
        Logger.info("Processing push notification")

        // Clean up old services before processing
        cleanupStaleServices()

        guard payload.isValid else {
            Logger.info("Dropping notification without clientId (v1/legacy)")
            return nil
        }

        guard let clientId = payload.clientId else {
            Logger.info("Dropping notification without clientId")
            return nil
        }

        Logger.info("Processing v2 notification for clientId: \(clientId)")
        let inboxesRepository = InboxesRepository(databaseReader: databaseReader)
        guard let inbox = try? inboxesRepository.inbox(byClientId: clientId) else {
            Logger.warning("No inbox found in database for clientId: \(clientId) - dropping notification")
            return nil
        }
        let inboxId = inbox.inboxId
        Logger.info("Matched clientId \(clientId) to inboxId: \(inboxId)")

        Logger.info("Processing for inbox: \(inboxId)")

        // Process with timeout
        return try await withTimeout(seconds: timeout, timeoutError: NotificationProcessingError.timeout) {
            let messagingService = await self.getOrCreateMessagingService(for: inboxId, clientId: clientId)
            return try await messagingService.processPushNotification(payload: payload)
        }
    }

    /// Cleans up all resources
    public func cleanup() {
        Logger.info("Cleaning up \(messagingServices.count) messaging services")
        messagingServices.values.forEach { $0.stop() }
        messagingServices.removeAll()
        lastAccessTime.removeAll()
        processedPayload = nil
    }

    /// Cleans up stale services that haven't been used recently
    private func cleanupStaleServices() {
        let now = Date()
        var staleInboxIds: [String] = []

        for (inboxId, accessTime) in lastAccessTime where now.timeIntervalSince(accessTime) > maxServiceAge {
            staleInboxIds.append(inboxId)
        }

        if !staleInboxIds.isEmpty {
            Logger.info("Cleaning up \(staleInboxIds.count) stale messaging services")
            for inboxId in staleInboxIds {
                let removedService = messagingServices.removeValue(forKey: inboxId)
                removedService?.stop()
                lastAccessTime.removeValue(forKey: inboxId)
            }
        }
    }

    // MARK: - Private Methods

    private func getOrCreateMessagingService(for inboxId: String, clientId: String) -> MessagingService {
        // Update access time
        lastAccessTime[inboxId] = Date()

        if let existing = messagingServices[inboxId] {
            Logger.info("Reusing existing messaging service for inbox: \(inboxId)")
            return existing
        }

        Logger.info("Creating new messaging service for inbox: \(inboxId), clientId: \(clientId)")
        let messagingService = MessagingService.authorizedMessagingService(
            for: inboxId,
            clientId: clientId,
            databaseWriter: databaseWriter,
            databaseReader: databaseReader,
            environment: environment,
            startsStreamingServices: false,
            autoRegistersForPushNotifications: false  // NSE: Skip push notification registration
        )
        messagingServices[inboxId] = messagingService
        return messagingService
    }
}
