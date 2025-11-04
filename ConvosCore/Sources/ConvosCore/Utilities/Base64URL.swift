import Foundation

// MARK: - Base64URL Extensions

/// URL-safe Base64 encoding/decoding for compact invite codes and metadata
///
/// Replaces standard base64 characters with URL-safe alternatives:
/// - `+` → `-`
/// - `/` → `_`
/// - Removes padding `=`
///
/// Used for encoding compressed protobuf payloads in invite URLs and metadata storage.
public extension Data {
    /// Encode data to URL-safe base64 string without padding
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

public extension String {
    /// Decode URL-safe base64 string to data
    func base64URLDecoded() throws -> Data {
        var base64 = self
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        // Add padding if needed
        let padding = 4 - (base64.count % 4)
        if padding < 4 {
            base64 += String(repeating: "=", count: padding)
        }

        guard let data = Data(base64Encoded: base64) else {
            throw Base64URLError.invalidFormat
        }

        return data
    }
}

// MARK: - Error Types

public enum Base64URLError: Error, LocalizedError {
    case invalidFormat

    public var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "Invalid base64url format"
        }
    }
}
