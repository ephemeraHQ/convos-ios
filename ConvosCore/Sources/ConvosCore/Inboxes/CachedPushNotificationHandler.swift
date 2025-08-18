import Combine
import Foundation
import GRDB

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

    /// Handles a push notification using the structured payload
    /// - Parameter userInfo: The raw notification userInfo dictionary
    public func handlePushNotification(userInfo: [AnyHashable: Any]) {
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

        // Get or create processor for this inbox
        let processor = getOrCreateProcessor(for: inboxId)

        // Use the push notification specific method
        processor.processPushNotification(payload: payload)
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
