import CryptoKit
import Foundation

/// Compact, public invite conversation tokens that only the creator can decode.
///
/// ## Cryptographic Design
/// - **Key Derivation**: HKDF-SHA256(privateKey, salt="ConvosInviteV1", info="inbox:<inboxId>")
/// - **AEAD**: ChaCha20-Poly1305 with AAD = creatorInboxId (binds token to creator's identity)
///
/// ## Binary Format Specification
/// ```
/// | version (1 byte) | chacha20poly1305_combined |
///
/// Where chacha20poly1305_combined contains:
/// | nonce (12 bytes) | ciphertext (variable) | auth_tag (16 bytes) |
///
/// And ciphertext decrypts to:
/// | type_tag (1 byte) | payload (variable) |
/// ```
///
/// ### Payload Types
/// - `type_tag = 0x01`: UUID format
///   - Payload: 16 bytes (raw UUID bytes)
///   - Total ciphertext: 17 bytes (before encryption)
/// - `type_tag = 0x02`: UTF-8 String format
///   - Payload (≤255 chars): | length (1 byte) | utf8_data |
///   - Payload (>255 chars): | 0x00 | length_high (1 byte) | length_low (1 byte) | utf8_data |
///   - Variable size based on string length
///
/// ## Size Analysis
/// - **Minimum size**: 46 bytes (version + nonce + type_tag + auth_tag = 1 + 12 + 1 + 16 = 30 bytes encoded)
/// - **UUID token**: 46 bytes encrypted → ~62 chars base64url
/// - **String token**: 30 + string_length bytes → varies by conversation ID length
enum InviteConversationToken {
    // MARK: - Format Constants

    /// Current format version
    static let formatVersion: UInt8 = 1

    /// Salt for HKDF key derivation
    private static let salt: Data = Data("ConvosInviteV1".utf8)

    /// ChaCha20-Poly1305 constants
    private static let nonceLength: Int = 12
    private static let authTagLength: Int = 16

    /// Minimum valid token size (version + nonce + type_tag + auth_tag)
    static let minEncodedSize: Int = 1 + nonceLength + 3 + authTagLength // 32 bytes

    /// Size of UUID-based tokens (fixed)
    static let uuidCodeSize: Int = 1 + nonceLength + 16 + 1 + authTagLength // 46 bytes

    /// Maximum supported string length for conversation IDs
    static let maxStringLength: Int = 65535 // 2-byte length field max

    // MARK: - Implementation

    private static let version: UInt8 = formatVersion

    // MARK: - Public API

    /// Make a public invite conversation token that the creator can later decrypt to the conversationId.
    /// - Parameters:
    ///   - conversationId: The conversation id (UUID string recommended; detected & packed into 16 bytes).
    ///   - creatorInboxId: The creator's inbox id (used for domain separation & AAD).
    ///   - secp256k1PrivateKey: 32-byte raw secp256k1 private key data.
    /// - Returns: Raw bytes of opaque conversation token.
    static func makeConversationTokenBytes(
        conversationId: String,
        creatorInboxId: String,
        secp256k1PrivateKey: Data
    ) throws -> Data {
        let key = try deriveKey(privateKey: secp256k1PrivateKey, inboxId: creatorInboxId)

        // Pack plaintext as either UUID(16) or UTF-8 with a tiny tag
        let plaintext = try packConversationId(conversationId)

        // AAD binds this token to the specific creator identity
        let aad = Data(creatorInboxId.utf8)

        let sealed = try chachaSeal(plaintext: plaintext, key: key, aad: aad)

        // Prepend version to CryptoKit's combined (nonce|ciphertext|tag)
        var out = Data()
        out.append(version)
        out.append(sealed.combined)

        return out
    }

    /// Make a public invite conversation token that the creator can later decrypt to the conversationId.
    /// - Parameters:
    ///   - conversationId: The conversation id (UUID string recommended; detected & packed into 16 bytes).
    ///   - creatorInboxId: The creator's inbox id (used for domain separation & AAD).
    ///   - secp256k1PrivateKey: 32-byte raw secp256k1 private key data.
    /// - Returns: Base64URL (no padding) opaque conversation token suitable for URLs.
    @available(*, deprecated, message: "Use makeConversationTokenBytes instead for better compression")
    static func makeConversationToken(
        conversationId: String,
        creatorInboxId: String,
        secp256k1PrivateKey: Data
    ) throws -> String {
        return try makeConversationTokenBytes(
            conversationId: conversationId,
            creatorInboxId: creatorInboxId,
            secp256k1PrivateKey: secp256k1PrivateKey
        ).base64URLEncoded()
    }

    /// Recover the original conversationId from a public invite conversation token (raw bytes).
    /// - Parameters:
    ///   - conversationTokenBytes: Raw bytes produced by `makeConversationTokenBytes`.
    ///   - creatorInboxId: Same inbox id used when generating the token.
    ///   - secp256k1PrivateKey: Same 32-byte private key used when generating.
    /// - Returns: The original conversationId on success.
    static func decodeConversationTokenBytes(
        _ conversationTokenBytes: Data,
        creatorInboxId: String,
        secp256k1PrivateKey: Data
    ) throws -> String {
        // Validate minimum size
        guard conversationTokenBytes.count >= minEncodedSize else {
            throw Error.invalidFormat("Code too short: \(conversationTokenBytes.count) bytes, minimum \(minEncodedSize)")
        }

        guard let ver = conversationTokenBytes.first else {
            throw Error.missingVersion
        }
        guard ver == formatVersion else {
            throw Error.unsupportedVersion(ver)
        }

        // Strip version; what remains must be a valid ChaChaPoly combined box
        let combined = conversationTokenBytes.dropFirst()
        let key = try deriveKey(privateKey: secp256k1PrivateKey, inboxId: creatorInboxId)
        let aad = Data(creatorInboxId.utf8)

        let plaintext = try chachaOpen(combined: combined, key: key, aad: aad)
        return try unpackConversationId(plaintext)
    }

    /// Recover the original conversationId from a public invite conversation token.
    /// - Parameters:
    ///   - conversationToken: Base64URL opaque string produced by `makeConversationToken`.
    ///   - creatorInboxId: Same inbox id used when generating the token.
    ///   - secp256k1PrivateKey: Same 32-byte private key used when generating.
    /// - Returns: The original conversationId on success.
    @available(*, deprecated, message: "Use decodeConversationTokenBytes instead for better compression")
    static func decodeConversationToken(
        _ conversationToken: String,
        creatorInboxId: String,
        secp256k1PrivateKey: Data
    ) throws -> String {
        let data = try conversationToken.base64URLDecoded()
        return try decodeConversationTokenBytes(
            data,
            creatorInboxId: creatorInboxId,
            secp256k1PrivateKey: secp256k1PrivateKey
        )
    }

    // MARK: - Errors

    enum Error: Swift.Error, LocalizedError {
        case truncated
        case missingVersion
        case unsupportedVersion(UInt8)
        case badKeyMaterial
        case cryptoOpenFailed
        case invalidFormat(String)
        case stringTooLong(Int)
        case emptyConversationId

        var errorDescription: String? {
            switch self {
            case .truncated:
                return "Invite code data is truncated"
            case .missingVersion:
                return "Invite code is missing version byte"
            case .unsupportedVersion(let version):
                return "Unsupported invite code version: \(version), expected \(InviteConversationToken.formatVersion)"
            case .badKeyMaterial:
                return "Invalid private key material"
            case .cryptoOpenFailed:
                return "Failed to decrypt invite code"
            case .invalidFormat(let details):
                return "Invalid invite code format: \(details)"
            case .stringTooLong(let length):
                return "Conversation ID too long: \(length) bytes, max \(InviteConversationToken.maxStringLength)"
            case .emptyConversationId:
                return "Conversation ID cannot be empty"
            }
        }
    }

    // MARK: - Internals

    private static func deriveKey(privateKey: Data, inboxId: String) throws -> SymmetricKey {
        // Expect 32-byte secp256k1 scalar; allow other lengths but still derive.
        guard !privateKey.isEmpty else { throw Error.badKeyMaterial }
        let info = Data(("inbox:" + inboxId).utf8)

        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: privateKey),
            salt: salt,
            info: info,
            outputByteCount: 32
        )
    }

    private static func chachaSeal(plaintext: Data, key: SymmetricKey, aad: Data) throws -> ChaChaPoly.SealedBox {
        let nonce = ChaChaPoly.Nonce() // random 12 bytes
        return try ChaChaPoly.seal(plaintext, using: key, nonce: nonce, authenticating: aad)
    }

    private static func chachaOpen(combined: Data, key: SymmetricKey, aad: Data) throws -> Data {
        let box: ChaChaPoly.SealedBox
        do {
            box = try ChaChaPoly.SealedBox(combined: combined)
        } catch {
            throw Error.invalidFormat("Malformed encrypted data")
        }

        do {
            return try ChaChaPoly.open(box, using: key, authenticating: aad)
        } catch {
            throw Error.cryptoOpenFailed
        }
    }

    // MARK: - ConversationId packing (shorter for UUIDs)

    /// Plaintext layout:
    ///   [tag:1][payload...]
    ///   tag = 0x01 -> UUID (16 bytes)
    ///   tag = 0x02 -> UTF-8 string (1 byte length if <=255, else 2 bytes big-endian + data)
    private enum PlainTag: UInt8 { case uuid16 = 0x01, utf8 = 0x02 }

    private static func packConversationId(_ id: String) throws -> Data {
        // Validate that conversation ID is not empty
        guard !id.isEmpty else {
            throw Error.emptyConversationId
        }

        var out = Data()
        if let uuid = UUID(uuidString: id) {
            out.append(PlainTag.uuid16.rawValue)
            var u = uuid.uuid
            // 16 bytes
            withUnsafeBytes(of: &u) { out.append(contentsOf: $0) }
            return out
        } else {
            out.append(PlainTag.utf8.rawValue)
            let bytes = Data(id.utf8)

            // Validate string length
            guard bytes.count <= maxStringLength else {
                throw Error.stringTooLong(bytes.count)
            }

            if !bytes.isEmpty && bytes.count <= 255 {
                out.append(UInt8(bytes.count))
            } else {
                // 0 length byte is a sentinel for 2-byte big-endian length
                // Use this format for empty strings (count == 0) and long strings (count > 255)
                out.append(0)
                out.append(UInt8((bytes.count >> 8) & 0xff))
                out.append(UInt8(bytes.count & 0xff))
            }
            out.append(bytes)
            return out
        }
    }

    private static func unpackConversationId(_ data: Data) throws -> String {
        guard let tagByte = data.first, let tag = PlainTag(rawValue: tagByte) else {
            throw Error.invalidFormat("Missing or invalid type tag")
        }
        var offset = 1
        switch tag {
        case .uuid16:
            guard data.count >= offset + 16 else {
                throw Error.invalidFormat("UUID payload too short: need 16 bytes, have \(data.count - offset)")
            }
            let slice = data[offset ..< offset + 16]
            offset += 16
            let uuid = slice.withUnsafeBytes { ptr -> UUID in
                let tup = ptr.bindMemory(to: UInt8.self)
                // Copy 16 bytes into uuid_t
                return UUID(uuid: (
                    tup[0], tup[1], tup[2], tup[3],
                    tup[4], tup[5], tup[6], tup[7],
                    tup[8], tup[9], tup[10], tup[11],
                    tup[12], tup[13], tup[14], tup[15]
                ))
            }
            return uuid.uuidString.lowercased()
        case .utf8:
            guard data.count > offset else {
                throw Error.invalidFormat("String payload missing length byte")
            }
            let len1 = Int(data[offset]); offset += 1
            let length: Int
            if len1 > 0 {
                length = len1
            } else {
                guard data.count >= offset + 2 else {
                    throw Error.invalidFormat("String payload missing 2-byte length")
                }
                length = (Int(data[offset]) << 8) | Int(data[offset + 1])
                offset += 2
            }

            // Validate that length is not zero
            guard length > 0 else {
                throw Error.emptyConversationId
            }

            guard data.count >= offset + length else {
                throw Error.invalidFormat("String payload truncated: need \(length) bytes, have \(data.count - offset)")
            }
            let bytes = data[offset ..< offset + length]
            guard let s = String(data: bytes, encoding: .utf8) else {
                throw Error.invalidFormat("Invalid UTF-8 string data")
            }
            return s
        }
    }
}
