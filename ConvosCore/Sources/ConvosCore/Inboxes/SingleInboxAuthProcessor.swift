import Combine
import Foundation
import GRDB

/// A processor that handles single inbox operations for scenarios like push notifications.
/// It fetches a single inbox, authorizes it, and executes work when ready.
public class SingleInboxAuthProcessor {
    private let authService: any LocalAuthServiceProtocol
    private let databaseReader: any DatabaseReader
    private let databaseWriter: any DatabaseWriter
    private let environment: AppEnvironment

    private var operation: AuthorizeInboxOperation?
    private var cancellables: Set<AnyCancellable> = []

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

    deinit {
        cleanup()
    }

    /// Processes a single inbox by ID and executes work when ready
    /// - Parameters:
    ///   - inboxId: The inbox ID to process
    ///   - timeout: Timeout duration for inbox authorization (default: 30 seconds)
    ///   - work: The work to execute when the inbox is ready
    /// - Returns: A publisher that emits the result of the work
    public func processInbox<T>(
        inboxId: String,
        timeout: TimeInterval = 30,
        work: @escaping (InboxReadyResult) async throws -> T
    ) -> AnyPublisher<T, Error> {
        cleanup()

        return Future<T, Error> { [weak self] promise in
                            guard let self = self else {
                    promise(.failure(SingleInboxAuthProcessorError.processorDeallocated))
                    return
                }

            do {
                // Fetch the inbox from auth service
                guard let inbox = try self.authService.inbox(for: inboxId) else {
                    promise(.failure(SingleInboxAuthProcessorError.inboxNotFound(inboxId)))
                    return
                }

                // Create and start the operation
                self.operation = AuthorizeInboxOperation(
                    inbox: inbox,
                    authService: self.authService,
                    databaseReader: self.databaseReader,
                    databaseWriter: self.databaseWriter,
                    environment: self.environment
                )

                // Set up timeout timer
                let timeoutTimer = Timer.publish(every: timeout, on: .main, in: .common)
                    .autoconnect()
                    .first()
                    .sink { _ in
                        promise(.failure(SingleInboxAuthProcessorError.timeout(inboxId)))
                    }

                // Subscribe to the ready publisher
                self.operation?.inboxReadyPublisher
                    .first()
                    .sink(
                        receiveCompletion: { completion in
                            switch completion {
                            case .finished:
                                timeoutTimer.cancel()
                            case .failure(let error):
                                timeoutTimer.cancel()
                                promise(.failure(error))
                            }
                        },
                        receiveValue: { inboxReadyResult in
                            timeoutTimer.cancel()
                            Task {
                                do {
                                    let result = try await work(inboxReadyResult)
                                    promise(.success(result))
                                } catch {
                                    promise(.failure(error))
                                }
                            }
                        }
                    )
                    .store(in: &self.cancellables)

                timeoutTimer.store(in: &self.cancellables)

                // Start authorization
                self.operation?.authorize()
            } catch {
                promise(.failure(error))
            }
        }
        .eraseToAnyPublisher()
    }

    /// Stops the current operation and cleans up resources
    public func stop() {
        cleanup()
    }

    private func cleanup() {
        operation?.stop()
        operation = nil
        cancellables.removeAll()
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
