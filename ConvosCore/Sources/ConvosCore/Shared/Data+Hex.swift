import Foundation

// MARK: - Hex Encoding Extensions

/// Hex encoding/decoding utilities for binary data
///
/// Used extensively for XMTP inbox IDs which are 64-character hex strings representing 32 bytes.
/// Storing inbox IDs as hex-decoded bytes in protobuf reduces size by ~50% (64 chars → 32 bytes).
extension Data {
    struct HexEncodingOptions: OptionSet {
        let rawValue: Int
        static let upperCase: HexEncodingOptions = .init(rawValue: 1 << 0)
    }

    /// Encode bytes to hex string
    /// - Parameter options: Encoding options (default: lowercase)
    /// - Returns: Hex-encoded string (e.g., "a1b2c3d4...")
    func hexEncodedString(options: HexEncodingOptions = []) -> String {
        let format = options.contains(.upperCase) ? "%02hhX" : "%02hhx"
        return self.map { String(format: format, $0) }.joined()
    }

    /// Encode bytes to hex string (lowercase)
    var toHex: String {
        return reduce("") { $0 + String(format: "%02x", $1) }
    }

    /// Decode hex string to bytes
    /// - Parameter hexString: Hex string with optional "0x" prefix
    /// - Returns: Decoded bytes, or nil if string is invalid hex
    init?(hexString: String) {
        var hex = hexString
        if hex.hasPrefix("0x") {
            hex = String(hex.dropFirst(2))
        }

        guard hex.count.isMultiple(of: 2) else { return nil }

        var newData = Data()
        var index = hex.startIndex

        for _ in 0..<(hex.count / 2) {
            let nextIndex = hex.index(index, offsetBy: 2)
            if let b = UInt8(hex[index..<nextIndex], radix: 16) {
                newData.append(b)
            } else {
                return nil
            }
            index = nextIndex
        }

        self = newData
    }
}
