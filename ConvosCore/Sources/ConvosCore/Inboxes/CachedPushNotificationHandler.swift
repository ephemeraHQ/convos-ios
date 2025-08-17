import Combine
import Foundation
import GRDB

/// Example usage of SingleInboxAuthProcessor for push notifications with caching
public class CachedPushNotificationHandler {
    private var processors: [String: SingleInboxAuthProcessor] = [:]
    private var cancellables: Set<AnyCancellable> = []

    private let authService: any LocalAuthServiceProtocol
    private let databaseReader: any DatabaseReader
    private let databaseWriter: any DatabaseWriter
    private let environment: AppEnvironment

    public init(
        authService: any LocalAuthServiceProtocol,
        databaseReader: any DatabaseReader,
        databaseWriter: any DatabaseWriter,
        environment: AppEnvironment
    ) {
        self.authService = authService
        self.databaseReader = databaseReader
        self.databaseWriter = databaseWriter
        self.environment = environment
    }

    /// Handles a push notification by processing the inbox and executing work
    /// - Parameter notificationData: The push notification payload
    public func handlePushNotification(notificationData: [AnyHashable: Any]) {
        guard let inboxId = notificationData["inboxId"] as? String else {
            Logger.error("Push notification missing inboxId")
            return
        }

        Logger.info("Processing push notification for inbox: \(inboxId)")

        // Get or create processor for this inbox
        let processor = getOrCreateProcessor(for: inboxId)

        // Use the push notification specific method
        processor.processPushNotification(notificationData: notificationData)
        .sink(
            receiveCompletion: { completion in
                switch completion {
                case .finished:
                    Logger.info("Push notification processing completed")
                case .failure(let error):
                    Logger.error("Push notification processing failed: \(error)")
                }
            },
            receiveValue: { _ in
                Logger.info("Push notification processed successfully")
            }
        )
        .store(in: &cancellables)
    }

    /// Schedules custom work for a specific inbox
    /// - Parameters:
    ///   - inboxId: The inbox ID to process
    ///   - timeout: Timeout duration for inbox authorization (default: 30 seconds)
    ///   - customWork: Custom work to perform when inbox is ready
    public func scheduleCustomWork<T>(
        for inboxId: String,
        timeout: TimeInterval = 30,
        customWork: @escaping (InboxReadyResult) async throws -> T
    ) -> AnyPublisher<T, Error> {
        let processor = getOrCreateProcessor(for: inboxId)
        return processor.scheduleWork(timeout: timeout, work: customWork)
    }

    /// Checks if an inbox is ready (cached)
    /// - Parameter inboxId: The inbox ID to check
    /// - Returns: True if the inbox is ready and cached
    public func isInboxReady(inboxId: String) -> Bool {
        return processors[inboxId]?.isReady ?? false
    }

    /// Gets the cached ready result for an inbox if available
    /// - Parameter inboxId: The inbox ID
    /// - Returns: The cached InboxReadyResult if available
    public func getCachedResult(for inboxId: String) -> InboxReadyResult? {
        return processors[inboxId]?.readyResult
    }

    /// Cleans up resources for a specific inbox
    /// - Parameter inboxId: The inbox ID to clean up
    public func cleanupInbox(inboxId: String) {
        processors[inboxId]?.stop()
        processors.removeValue(forKey: inboxId)
    }

    /// Cleans up all resources
    public func cleanup() {
        for processor in processors.values {
            processor.stop()
        }
        processors.removeAll()
        cancellables.removeAll()
    }

    // MARK: - Private Methods

    private func getOrCreateProcessor(for inboxId: String) -> SingleInboxAuthProcessor {
        if let existingProcessor = processors[inboxId] {
            return existingProcessor
        }

        let processor = SingleInboxAuthProcessor(
            inboxId: inboxId,
            authService: authService,
            databaseReader: databaseReader,
            databaseWriter: databaseWriter,
            environment: environment
        )

        processors[inboxId] = processor
        return processor
    }
}

// MARK: - Example Usage

/*
 Example usage in your notification extension:

 // In your NotificationServiceExtension
 let pushHandler = CachedPushNotificationHandler(
     authService: secureEnclaveAuthService,
     databaseReader: databaseManager.dbReader,
     databaseWriter: databaseManager.dbWriter,
     environment: environment
 )

 // Handle multiple push notifications for the same inbox efficiently
 func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
     let userInfo = request.content.userInfo

     // This will reuse the cached inbox if already authorized
     pushHandler.handlePushNotification(notificationData: userInfo)

     // Schedule additional work for the same inbox
     if let inboxId = userInfo["inboxId"] as? String {
         pushHandler.scheduleCustomWork(for: inboxId) { inboxReadyResult in
             // Additional work when inbox is ready
             let client = inboxReadyResult.client
             let apiClient = inboxReadyResult.apiClient

             // Do something with the ready inbox
             try await apiClient.someEndpoint()
             return "Custom result"
         }
         .sink(
             receiveCompletion: { completion in
                 // Handle completion
             },
             receiveValue: { result in
                 // Handle result
             }
         )
         .store(in: &cancellables)
     }

     contentHandler(request.content)
 }

 // Check if inbox is ready before scheduling work
 if pushHandler.isInboxReady(inboxId: "some-inbox-id") {
     // Inbox is already cached, work will execute immediately
     pushHandler.scheduleCustomWork(for: "some-inbox-id") { inboxReadyResult in
         // This will execute immediately since inbox is cached
         return "Immediate result"
     }
     .sink { result in
         // Handle immediate result
     }
     .store(in: &cancellables)
 }
 */
