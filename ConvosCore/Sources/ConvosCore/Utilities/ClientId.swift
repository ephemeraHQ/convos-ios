import Foundation

/// A client identifier used to anonymize inbox IDs when communicating with the backend.
/// This provides privacy by not exposing the actual XMTP inbox ID to external services.
public struct ClientId: Codable, Hashable, Equatable {
    public let value: String

    /// Generate a new random client ID as a UUID
    public static func generate() -> ClientId {
        return ClientId(value: UUID().uuidString)
    }

    /// Create a client ID from a string value
    public init(value: String) {
        self.value = value
    }
}

extension ClientId: CustomStringConvertible {
    public var description: String {
        value
    }
}

extension ClientId: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.value = value
    }
}
