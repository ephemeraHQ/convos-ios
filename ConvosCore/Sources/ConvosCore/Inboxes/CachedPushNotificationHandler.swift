import Combine
import Foundation
import GRDB

// MARK: - Errors
public enum NotificationProcessingError: Error {
    case timeout
    case invalidPayload
}

// MARK: - Global Actor
@globalActor
public actor CachedPushNotificationHandler {
    public static var shared: CachedPushNotificationHandler {
        guard _shared != nil else {
            fatalError("CachedPushNotificationHandler.initialize() must be called before accessing shared")
        }
        // swiftlint:disable:next force_unwrapping
        return _shared!
    }
    private static var _shared: CachedPushNotificationHandler?

    /// Initialize the shared instance with required dependencies
    /// - Parameters:
    ///   - databaseReader: Database reader instance
    ///   - databaseWriter: Database writer instance
    ///   - environment: App environment
    public static func initialize(
        databaseReader: any DatabaseReader,
        databaseWriter: any DatabaseWriter,
        environment: AppEnvironment
    ) {
        _shared = CachedPushNotificationHandler(
            databaseReader: databaseReader,
            databaseWriter: databaseWriter,
            environment: environment
        )
    }

    private let databaseReader: any DatabaseReader
    private let databaseWriter: any DatabaseWriter
    private let environment: AppEnvironment

    private init(
        databaseReader: any DatabaseReader,
        databaseWriter: any DatabaseWriter,
        environment: AppEnvironment
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
            let messagingService = await self.getOrCreateMessagingService(for: inboxId, clientId: clientId, overrideJWTToken: payload.apiJWT)
            return try await messagingService.processPushNotification(payload: payload)
        }
    }

    // MARK: - Private Methods

    private func getOrCreateMessagingService(for inboxId: String, clientId: String, overrideJWTToken: String?) -> MessagingService {
        // Each notification has a unique JWT, so we always create a fresh MessagingService
        Logger.info("Creating new messaging service for notification with JWT override")
        return MessagingService.authorizedMessagingService(
            for: inboxId,
            clientId: clientId,
            databaseWriter: databaseWriter,
            databaseReader: databaseReader,
            environment: environment,
            startsStreamingServices: false,
            overrideJWTToken: overrideJWTToken
        )
    }
}
