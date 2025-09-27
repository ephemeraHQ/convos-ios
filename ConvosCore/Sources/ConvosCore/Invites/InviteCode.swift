import CryptoKit
import Foundation

/// Compact, public invite codes that only the creator can decode.
/// - Symmetric key: HKDF-SHA256(privateKey, salt="ConvosInviteV1", info="inbox:<inboxId>")
/// - AEAD: ChaCha20-Poly1305, AAD = creatorInboxId (binds code to the creator’s identity)
/// - Format (bytes): [version:1][ChaChaPoly.combined]
///   where `combined` = nonce(12) || ciphertext || tag(16)
enum InviteCodeCrypto {
    private static let version: UInt8 = 1
    private static let salt: Data = Data("ConvosInviteV1".utf8)

    // MARK: - Public API

    /// Make a public invite code that the creator can later decrypt to the conversationId.
    /// - Parameters:
    ///   - conversationId: The conversation id (UUID string recommended; detected & packed into 16 bytes).
    ///   - creatorInboxId: The creator’s inbox id (used for domain separation & AAD).
    ///   - secp256k1PrivateKey: 32-byte raw secp256k1 private key data.
    /// - Returns: Base64URL (no padding) opaque code suitable for URLs.
    static func makeCode(
        conversationId: String,
        creatorInboxId: String,
        secp256k1PrivateKey: Data
    ) throws -> String {
        let key = try deriveKey(privateKey: secp256k1PrivateKey, inboxId: creatorInboxId)

        // Pack plaintext as either UUID(16) or UTF-8 with a tiny tag
        let plaintext = try packConversationId(conversationId)

        // AAD binds this code to the specific creator identity
        let aad = Data(creatorInboxId.utf8)

        let sealed = try chachaSeal(plaintext: plaintext, key: key, aad: aad)

        // Prepend version to CryptoKit's combined (nonce|ciphertext|tag)
        var out = Data()
        out.append(version)
        out.append(sealed.combined)

        return out.base64URLEncoded()
    }

    /// Recover the original conversationId from a public invite code.
    /// - Parameters:
    ///   - code: Base64URL opaque string produced by `makeCode`.
    ///   - creatorInboxId: Same inbox id used when generating the code.
    ///   - secp256k1PrivateKey: Same 32-byte private key used when generating.
    /// - Returns: The original conversationId on success.
    static func decodeCode(
        _ code: String,
        creatorInboxId: String,
        secp256k1PrivateKey: Data
    ) throws -> String {
        let data = try code.base64URLDecoded()
        guard data.count > 1 else { throw Error.truncated }
        guard let ver = data.first else {
            throw Error.missingVersion
        }
        guard ver == version else { throw Error.unsupportedVersion(ver) }

        // Strip version; what remains must be a valid ChaChaPoly combined box
        let combined = data.dropFirst()
        let key = try deriveKey(privateKey: secp256k1PrivateKey, inboxId: creatorInboxId)
        let aad = Data(creatorInboxId.utf8)

        let plaintext = try chachaOpen(combined: combined, key: key, aad: aad)
        return try unpackConversationId(plaintext)
    }

    // MARK: - Errors

    enum Error: Swift.Error {
        case truncated
        case missingVersion
        case unsupportedVersion(UInt8)
        case badKeyMaterial
        case cryptoOpenFailed
        case invalidFormat
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
        let box = try ChaChaPoly.SealedBox(combined: combined)
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
            if bytes.count <= 255 {
                out.append(UInt8(bytes.count))
            } else {
                // 0 length means use 2-byte big-endian length next
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
            throw Error.invalidFormat
        }
        var offset = 1
        switch tag {
        case .uuid16:
            guard data.count >= offset + 16 else { throw Error.truncated }
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
            return uuid.uuidString.lowercased() // or keep original casing if you prefer
        case .utf8:
            guard data.count > offset else { throw Error.truncated }
            let len1 = Int(data[offset]); offset += 1
            let length: Int
            if len1 > 0 {
                length = len1
            } else {
                guard data.count >= offset + 2 else { throw Error.truncated }
                length = (Int(data[offset]) << 8) | Int(data[offset + 1])
                offset += 2
            }
            guard data.count >= offset + length else { throw Error.truncated }
            let bytes = data[offset ..< offset + length]
            guard let s = String(data: bytes, encoding: .utf8) else { throw Error.invalidFormat }
            return s
        }
    }
}
