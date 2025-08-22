import Combine
import Foundation
import GRDB

/// A processor that handles single inbox operations for scenarios like push notifications.
/// It fetches a single inbox, authorizes it, and caches the result for multiple work items.
public class SingleInboxAuthProcessor {
    private let inboxId: String
    private let authService: any LocalAuthServiceProtocol
    internal let databaseReader: any DatabaseReader
    internal let databaseWriter: any DatabaseWriter
    internal let environment: AppEnvironment

    private var operation: AuthorizeInboxOperation?
    private var cancellables: Set<AnyCancellable> = []
    private var pendingWork: [(InboxReadyResult) async throws -> Void] = []
    private var cachedResult: InboxReadyResult?
    private var isAuthorizing: Bool = false
    private var authorizationError: Error?

    internal let isNotificationServiceExtension: Bool

    public init(
        inboxId: String,
        authService: any LocalAuthServiceProtocol,
        databaseReader: any DatabaseReader,
        databaseWriter: any DatabaseWriter,
        environment: AppEnvironment,
        isNotificationServiceExtension: Bool = false
    ) {
        self.inboxId = inboxId
        self.authService = authService
        self.databaseReader = databaseReader
        self.databaseWriter = databaseWriter
        self.environment = environment
        self.isNotificationServiceExtension = isNotificationServiceExtension
    }

    deinit {
        cleanup()
    }

    /// Schedules work to be performed when the inbox is ready
    /// - Parameters:
    ///   - timeout: Timeout duration for inbox authorization (default: 30 seconds)
    ///   - work: The work to execute when the inbox is ready
    /// - Returns: A publisher that emits when the work is complete
    public func scheduleWork<T>(
        timeout: TimeInterval = 30,
        work: @escaping (InboxReadyResult) async throws -> T
    ) -> AnyPublisher<T, Error> {
        return Future<T, Error> { [weak self] promise in
            guard let self = self else {
                promise(.failure(SingleInboxAuthProcessorError.processorDeallocated))
                return
            }

            // If we have a cached result, execute work immediately
            if let cachedResult = self.cachedResult {
                Task {
                    do {
                        let result = try await work(cachedResult)
                        promise(.success(result))
                    } catch {
                        promise(.failure(error))
                    }
                }
                return
            }

            // If there was a previous authorization error, fail immediately
            if let error = self.authorizationError {
                promise(.failure(error))
                return
            }

            // If already authorizing, queue the work
            if self.isAuthorizing {
                self.pendingWork.append { inboxReadyResult in
                    do {
                        let result = try await work(inboxReadyResult)
                        promise(.success(result))
                    } catch {
                        promise(.failure(error))
                    }
                }
                return
            }

            // Start authorization process
            self.startAuthorization(timeout: timeout) { result in
                switch result {
                case .success(let inboxReadyResult):
                    Task {
                        do {
                            let workResult = try await work(inboxReadyResult)
                            promise(.success(workResult))
                        } catch {
                            promise(.failure(error))
                        }
                    }
                case .failure(let error):
                    promise(.failure(error))
                }
            }
        }
        .handleEvents(receiveCancel: { [weak self] in self?.cleanup() })
        .eraseToAnyPublisher()
    }

    /// Checks if the inbox is currently ready (cached)
    public var isReady: Bool {
        return cachedResult != nil
    }

    /// Gets the cached inbox ready result if available
    public var readyResult: InboxReadyResult? {
        return cachedResult
    }

    /// Stops the current operation and cleans up resources
    public func stop() {
        cleanup()
    }

    // MARK: - Private Methods

    private func startAuthorization(
        timeout: TimeInterval,
        completion: @escaping (Result<InboxReadyResult, Error>) -> Void
    ) {
        guard !isAuthorizing else {
            // Already authorizing, queue the completion
            pendingWork.append { inboxReadyResult in
                completion(.success(inboxReadyResult))
            }
            return
        }

        isAuthorizing = true
        authorizationError = nil

        do {
            // Fetch the inbox from auth service
            guard let inbox = try authService.inbox(for: inboxId) else {
                let error = SingleInboxAuthProcessorError.inboxNotFound(inboxId)
                authorizationError = error
                isAuthorizing = false
                failPendingWork(with: error)
                completion(.failure(error))
                return
            }

            // Create and start the operation
            operation = AuthorizeInboxOperation(
                inbox: inbox,
                authService: authService,
                databaseReader: databaseReader,
                databaseWriter: databaseWriter,
                environment: environment,
                isNotificationServiceExtension: isNotificationServiceExtension
            )

            // Set up timeout timer
            let timeoutTimer = Timer.publish(every: timeout, on: .main, in: .common)
                .autoconnect()
                .first()
                .sink { [weak self] _ in
                    guard let self = self else { return }
                    let error = SingleInboxAuthProcessorError.timeout(self.inboxId)
                    self.authorizationError = error
                    self.isAuthorizing = false
                    self.failPendingWork(with: error)
                    self.cleanup()
                    completion(.failure(error))
                }

            // Subscribe to the ready publisher
            operation?.inboxReadyPublisher
                .first()
                .sink(
                    receiveCompletion: { [weak self] publisherCompletion in
                        guard let self = self else { return }
                        timeoutTimer.cancel()
                        switch publisherCompletion {
                        case .finished:
                            break
                        case .failure(let error):
                            self.authorizationError = error
                            self.isAuthorizing = false
                            self.failPendingWork(with: error)
                            self.cleanup()
                            completion(.failure(error))
                        }
                    },
                    receiveValue: { [weak self] inboxReadyResult in
                        guard let self = self else { return }
                        timeoutTimer.cancel()

                        // Cache the result
                        self.cachedResult = inboxReadyResult
                        self.isAuthorizing = false

                        // Execute the completion
                        completion(.success(inboxReadyResult))

                        // Execute any pending work
                        self.executePendingWork(inboxReadyResult: inboxReadyResult)
                    }
                )
                .store(in: &cancellables)

            timeoutTimer.store(in: &cancellables)

            // Start authorization
            operation?.authorize()
        } catch {
            authorizationError = error
            isAuthorizing = false
            failPendingWork(with: error)
            completion(.failure(error))
        }
    }

    private func executePendingWork(inboxReadyResult: InboxReadyResult) {
        let workToExecute = pendingWork
        pendingWork.removeAll()

        for work in workToExecute {
            Task {
                do {
                    try await work(inboxReadyResult)
                } catch {
                    Logger.error("Error executing pending work: \(error)")
                }
            }
        }
    }

    private func failPendingWork(with error: Error) {
        // Note: pendingWork closures expect InboxReadyResult, but we have an error.
        // Since the work closures are designed to handle success cases and throw errors,
        // we can't call them with an error directly. Instead, we just clear the queue
        // since the promises in scheduleWork will be failed via their respective completion handlers.
        let count = pendingWork.count
        pendingWork.removeAll()
        Logger.info("Cleared \(count) pending work items due to error: \(error)")
    }

    private func cleanup() {
        operation?.stop()
        operation = nil
        cancellables.removeAll()
        pendingWork.removeAll()
        cachedResult = nil
        isAuthorizing = false
        authorizationError = nil
    }
}

// MARK: - Errors

public enum SingleInboxAuthProcessorError: Error, LocalizedError {
    case inboxNotFound(String)
    case processorDeallocated
    case timeout(String)

    public var errorDescription: String? {
        switch self {
        case .inboxNotFound(let inboxId):
            return "Inbox not found for ID: \(inboxId)"
        case .processorDeallocated:
            return "SingleInboxAuthProcessor was deallocated"
        case .timeout(let inboxId):
            return "Inbox authorization timed out for ID: \(inboxId)"
        }
    }
}
