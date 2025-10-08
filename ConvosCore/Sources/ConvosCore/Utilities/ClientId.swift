import CryptoKit
import Foundation

/// A client identifier used to anonymize inbox IDs when communicating with the backend.
/// This provides privacy by not exposing the actual XMTP inbox ID to external services.
public struct ClientId: Codable, Hashable, Equatable {
    public let value: String

    /// Generate a new random client ID
    public static func generate() -> ClientId {
        let bytes = SymmetricKey(size: .bits128)
        let data = bytes.withUnsafeBytes { Data($0) }
        let base64 = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return ClientId(value: base64)
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


