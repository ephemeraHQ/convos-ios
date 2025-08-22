import Combine
import Foundation
import GRDB

// MARK: - Combine Async Extension
extension Publisher {
    func async() async throws -> Output {
        return try await withTaskCancellationHandler(
            operation: {
                try await withCheckedThrowingContinuation { continuation in
                    var cancellable: AnyCancellable?
                    var hasResumed = false
                    let lock = NSLock()

                    cancellable = self.sink(
                        receiveCompletion: { completion in
                            lock.lock()
                            guard !hasResumed else { lock.unlock(); return }
                            hasResumed = true
                            lock.unlock()

                            switch completion {
                            case .finished:
                                // Publisher completed without emitting a value
                                continuation.resume(throwing: CancellationError())
                            case .failure(let error):
                                continuation.resume(throwing: error)
                            }
                            cancellable?.cancel()
                        },
                        receiveValue: { value in
                            lock.lock()
                            guard !hasResumed else { lock.unlock(); return }
                            hasResumed = true
                            lock.unlock()

                            continuation.resume(returning: value)
                            cancellable?.cancel()
                        }
                    )

                    // Handle immediate task cancellation
                    if Task.isCancelled {
                        lock.lock()
                        let shouldResume = !hasResumed
                        hasResumed = true
                        lock.unlock()
                        if shouldResume {
                            cancellable?.cancel()
                            continuation.resume(throwing: CancellationError())
                        } else {
                            cancellable?.cancel()
                        }
                    }
                }
            },
            onCancel: {
                // The cancellation handler runs on a different execution context
                // and cannot directly access the continuation or cancellable
                // The Task.isCancelled check above handles immediate cancellation
                // For async cancellation, the Task will be cancelled and the operation will throw
            }
        )
    }
}

public class CachedPushNotificationHandler {
    private var processors: [String: SingleInboxAuthProcessor] = [:]
    private var cancellables: Set<AnyCancellable> = []

    // Store the processed payload for NSE access
    private var processedPayload: PushNotificationPayload?

    private let authService: any LocalAuthServiceProtocol
    private let databaseReader: any DatabaseReader
    private let databaseWriter: any DatabaseWriter
    private let environment: AppEnvironment
    private let isNotificationServiceExtension: Bool

    public init(
        authService: any LocalAuthServiceProtocol,
        databaseReader: any DatabaseReader,
        databaseWriter: any DatabaseWriter,
        environment: AppEnvironment,
        isNotificationServiceExtension: Bool = false
    ) {
        self.authService = authService
        self.databaseReader = databaseReader
        self.databaseWriter = databaseWriter
        self.environment = environment
        self.isNotificationServiceExtension = isNotificationServiceExtension
    }

    /// Handles a push notification using the structured payload
    /// - Parameter userInfo: The raw notification userInfo dictionary
    public func handlePushNotification(userInfo: [AnyHashable: Any]) {
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

    /// Handles a push notification asynchronously and waits for completion
    /// - Parameter userInfo: The raw notification userInfo dictionary
    /// - Returns: Async completion when processing is done
    /// - Throws: NotificationError.messageShouldBeDropped if the message should not be shown
    public func handlePushNotificationAsync(userInfo: [AnyHashable: Any]) async throws {
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

        // Get or create processor for this inbox
        let processor = getOrCreateProcessor(for: inboxId)

        // Store payload for NSE access
        self.processedPayload = payload

        // Use async/await to wait for completion
        do {
            _ = try await processor.processPushNotification(payload: payload).async()
            Logger.info("Push notification processed successfully")
        } catch {
            // Check if this is a notification that should be dropped
            if let error = error as? NotificationError, error == .messageShouldBeDropped {
                Logger.info("Re-throwing messageShouldBeDropped error")
                throw NotificationError.messageShouldBeDropped
            }
            // For other errors, just log them but don't re-throw
            Logger.error("Push notification processing failed: \(error)")
        }
    }

    /// Gets the processed payload with decoded content for NSE use
    public func getProcessedPayload() -> PushNotificationPayload? {
        return processedPayload
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
        Logger.info("CachedPushNotificationHandler: Starting cleanup of \(processors.count) processors")

        for processor in processors.values {
            processor.stop()
        }
        processors.removeAll()
        cancellables.removeAll()
        processedPayload = nil // Clear processed payload

        // For NSE, GRDB will handle database connection cleanup automatically when the process ends
        if isNotificationServiceExtension {
            Logger.info("NSE: Cleanup complete - all XMTP operations stopped, GRDB will handle database connection cleanup automatically")
        }
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
            environment: environment,
            isNotificationServiceExtension: isNotificationServiceExtension
        )

        processors[inboxId] = processor
        return processor
    }
}
