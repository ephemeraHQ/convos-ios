import Foundation

/// Errors that can occur during passkey authentication
public enum PasskeyError: LocalizedError {
    /// The URL is invalid
    case invalidURL(String)

    /// No data was received from the server
    case noData

    /// The challenge received from the server is invalid
    case invalidChallenge(String)

    /// The authentication failed
    case authenticationFailed(String)

    /// The registration failed
    case registrationFailed(String)

    /// Another authentication attempt is already in progress
    case authenticationInProgress

    /// The request was rate limited by the server
    case rateLimit(retryAfter: TimeInterval?)

    /// Network connectivity error
    case networkError(Error)

    /// Server error with status code
    case serverError(statusCode: Int, message: String?)

    /// JSON parsing error
    case jsonParsingError(Error)

    /// Configuration error
    case configurationError(String)

    /// Whether to include detailed error information
    private static var includeDebugInfo: Bool = false

    /// Sets whether to include detailed error information
    /// - Parameter include: Whether to include debug information
    public static func setDebugMode(_ include: Bool) {
        includeDebugInfo = include
    }

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let details):
            return Self.includeDebugInfo ? "The URL is invalid: \(details)" : "The URL is invalid"
        case .noData:
            return "No data was received from the server"
        case .invalidChallenge(let details):
            return (Self.includeDebugInfo ? "The challenge received from the server is invalid: \(details)"
                    : "The challenge received from the server is invalid")
        case .authenticationFailed(let details):
            return Self.includeDebugInfo ? "The authentication failed: \(details)" : "The authentication failed"
        case .registrationFailed(let details):
            return Self.includeDebugInfo ? "The registration failed: \(details)" : "The registration failed"
        case .authenticationInProgress:
            return "Another authentication attempt is already in progress"
        case .rateLimit(let retryAfter):
            if let retryAfter = retryAfter {
                let minutes = Int(ceil(retryAfter / 60))
                return "Too many requests. Please try again in \(minutes) minute\(minutes == 1 ? "" : "s")"
            }
            return "Too many requests. Please try again later"
        case .networkError(let error):
            return Self.includeDebugInfo ? "Network error: \(error.localizedDescription)" : "Network error occurred"
        case let .serverError(statusCode, message):
            if Self.includeDebugInfo {
                if let message = message {
                    return "Server error (\(statusCode)): \(message)"
                }
                return "Server error with status code: \(statusCode)"
            }
            return "Server error occurred"
        case .jsonParsingError(let error):
            return (Self.includeDebugInfo ?
                    "Failed to parse server response: \(error.localizedDescription)" :
                        "Failed to parse server response")
        case .configurationError(let details):
            return Self.includeDebugInfo ? "Configuration error: \(details)" : "Configuration error occurred"
        }
    }

    /// Returns a user-friendly recovery suggestion for the error
    public var recoverySuggestion: String? {
        switch self {
        case .invalidURL:
            return "Please check the server URL in your configuration"
        case .noData:
            return "Please check your internet connection and try again"
        case .invalidChallenge:
            return "Please try the operation again"
        case .authenticationFailed:
            return "Please verify your credentials and try again"
        case .registrationFailed:
            return "Please try registering again with a different display name"
        case .authenticationInProgress:
            return "Please wait for the current authentication to complete"
        case .rateLimit:
            return "Please wait a few minutes before trying again"
        case .networkError:
            return "Please check your internet connection and try again"
        case .serverError:
            return "Please try again later or contact support if the problem persists"
        case .jsonParsingError:
            return "Please try again or contact support if the problem persists"
        case .configurationError:
            return "Please check your configuration settings"
        }
    }

    /// Returns whether the error is likely temporary and retrying might help
    public var isRetryable: Bool {
        switch self {
        case .rateLimit, .networkError, .serverError:
            return true
        case .invalidURL, .noData, .invalidChallenge, .authenticationFailed,
             .registrationFailed, .authenticationInProgress, .jsonParsingError,
             .configurationError:
            return false
        }
    }
}
