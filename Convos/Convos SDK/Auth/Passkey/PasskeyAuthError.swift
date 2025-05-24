import Foundation

/// Errors that can occur during passkey authentication
public enum PasskeyError: LocalizedError {
    /// The challenge received from the server is invalid
    case invalidChallenge(String)

    /// The authentication failed
    case authenticationFailed(String)

    /// The registration failed
    case registrationFailed(String)

    /// Another authentication attempt is already in progress
    case authenticationInProgress

    case missingPresentationContextProvider

    /// Whether to include detailed error information
    private static var includeDebugInfo: Bool = false

    /// Sets whether to include detailed error information
    /// - Parameter include: Whether to include debug information
    public static func setDebugMode(_ include: Bool) {
        includeDebugInfo = include
    }

    public var errorDescription: String? {
        switch self {
        case .invalidChallenge(let details):
            return Self.includeDebugInfo ? "The challenge is invalid: \(details)" :
            "The challenge is invalid"
        case .authenticationFailed(let details):
            return Self.includeDebugInfo ? "The authentication failed: \(details)" : "The authentication failed"
        case .registrationFailed(let details):
            return Self.includeDebugInfo ? "The registration failed: \(details)" : "The registration failed"
        case .authenticationInProgress:
            return "Another authentication attempt is already in progress"
        case .missingPresentationContextProvider:
            return "Presentation context provider was not set"
        }
    }
}
