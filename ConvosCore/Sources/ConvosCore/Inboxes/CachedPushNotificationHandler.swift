import Combine
import Foundation
import GRDB

// MARK: - Errors
public enum NotificationProcessingError: Error {
    case timeout
    case invalidPayload
    case missingInboxId
}

public actor CachedPushNotificationHandler {
    private var messagingServices: [String: MessagingService] = [:]

    // Track last access time for cleanup
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
            Logger.error("Invalid push notification payload: \(payload)")
            return nil
        }

        guard let inboxId = payload.inboxId else {
            Logger.error("Push notification missing inboxId")
            return nil
        }

        Logger.info("Processing for inbox: \(inboxId), type: \(payload.notificationType?.displayName ?? "unknown")")

        // Process with timeout
        return try await withThrowingTaskGroup(of: DecodedNotificationContent?.self) { group in
            // Add the main processing task
            group.addTask { [weak self] in
                guard let self = self else { return nil }

                // Get or create messaging service for this inbox
                let messagingService = await self.getOrCreateMessagingService(for: inboxId)
                return try await messagingService.processPushNotification(payload: payload)
            }

            // Add timeout task
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw NotificationProcessingError.timeout
            }

            // Return first result (either success or timeout)
            if let result = try await group.next() {
                group.cancelAll() // Cancel the other task
                return result
            }

            return nil
        }
    }

    /// Cleans up all resources
    public func cleanup() {
        Logger.info("Cleaning up \(messagingServices.count) messaging services")
        messagingServices.removeAll()
        lastAccessTime.removeAll()
        processedPayload = nil
    }

    /// Cleans up stale services that haven't been used recently
    private func cleanupStaleServices() {
        let now = Date()
        var stalInboxIds: [String] = []

        for (inboxId, accessTime) in lastAccessTime where now.timeIntervalSince(accessTime) > maxServiceAge {
            stalInboxIds.append(inboxId)
        }

        if !stalInboxIds.isEmpty {
            Logger.info("Cleaning up \(stalInboxIds.count) stale messaging services")
            for inboxId in stalInboxIds {
                messagingServices.removeValue(forKey: inboxId)
                lastAccessTime.removeValue(forKey: inboxId)
            }
        }
    }

    // MARK: - Private Methods

    private func getOrCreateMessagingService(for inboxId: String) -> MessagingService {
        // Update access time
        lastAccessTime[inboxId] = Date()

        if let existing = messagingServices[inboxId] {
            Logger.info("Reusing existing messaging service for inbox: \(inboxId)")
            return existing
        }

        Logger.info("Creating new messaging service for inbox: \(inboxId)")
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
