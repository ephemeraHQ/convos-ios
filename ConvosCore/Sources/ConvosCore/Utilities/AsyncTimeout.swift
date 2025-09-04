import Foundation

// MARK: - Async Timeout Utility

/// Executes an async operation with a timeout
/// - Parameters:
///   - seconds: The timeout duration in seconds
///   - operation: The async operation to execute
/// - Returns: The result of the operation
/// - Throws: The error from the operation or a timeout error
public func withTimeout<T>(
    seconds: TimeInterval,
    operation: @escaping () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        // Add the main operation task
        group.addTask {
            try await operation()
        }

        // Add timeout task
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw TimeoutError()
        }

        // Wait for first to complete
        guard let result = try await group.next() else {
            throw TimeoutError()
        }

        // Cancel the other task
        group.cancelAll()

        return result
    }
}

/// Error thrown when an async operation times out
public struct TimeoutError: LocalizedError {
    public var errorDescription: String? {
        "The operation timed out"
    }
}

// MARK: - Alternative with custom timeout error

/// Executes an async operation with a timeout and custom error
/// - Parameters:
///   - seconds: The timeout duration in seconds
///   - timeoutError: The error to throw on timeout
///   - operation: The async operation to execute
/// - Returns: The result of the operation
/// - Throws: The error from the operation or the specified timeout error
public func withTimeout<T, E: Error>(
    seconds: TimeInterval,
    timeoutError: E,
    operation: @escaping () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        // Add the main operation task
        group.addTask {
            try await operation()
        }

        // Add timeout task with custom error
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw timeoutError
        }

        // Wait for first to complete
        guard let result = try await group.next() else {
            throw timeoutError
        }

        // Cancel the other task
        group.cancelAll()

        return result
    }
}
