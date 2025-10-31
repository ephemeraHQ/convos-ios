import Compression
import CryptoKit
import CSecp256k1
import Foundation
import SwiftProtobuf

/// Extensions for cryptographically signed conversation invites
///
/// Convos uses a secure invite system based on secp256k1 signatures:
///
/// **Invite Creation Flow:**
/// 1. Creator generates an invite containing: conversation token (encrypted conversation ID),
///    invite tag, metadata (name, image, description), and optional expiry
/// 2. Creator signs the invite payload with their private key
/// 3. Invite is encoded to a URL-safe base64 string (the "invite code")
///
/// **Join Request Flow:**
/// 1. Joiner receives invite code (QR, link, airdrop, etc.)
/// 2. Joiner sends the invite code as a text message in a DM to the creator
/// 3. Creator's app validates signature and decrypts conversation token
/// 4. If valid, creator adds joiner to the conversation
///
/// **Security Properties:**
/// - Only the creator can decrypt the conversation ID (via encrypted token)
/// - Signature proves the invite was created by conversation owner
/// - Public key can be recovered from signature for verification
/// - Invites can have expiration dates and single-use flags
/// - Invalid invites result in blocked DMs to prevent spam
extension SignedInvite {
    public var expiresAt: Date? {
        payload.expiresAtUnixIfPresent
    }

    public var hasExpired: Bool {
        guard let expiresAt else { return false }
        return Date() > expiresAt
    }

    public var conversationHasExpired: Bool {
        guard let conversationExpiresAt else { return false }
        return Date() > conversationExpiresAt
    }

    public var name: String? {
        payload.nameIfPresent
    }

    public var description_p: String? {
        payload.descriptionIfPresent
    }

    public var imageURL: String? {
        payload.imageURLIfPresent
    }

    public var conversationExpiresAt: Date? {
        payload.conversationExpiresAtUnixIfPresent
    }

    public var expiresAfterUse: Bool {
        payload.expiresAfterUse
    }

    public static func slug(
        for conversation: DBConversation,
        expiresAt: Date?,
        expiresAfterUse: Bool,
        privateKey: Data,
    ) throws -> String {
        let conversationTokenBytes = try InviteConversationToken.makeConversationTokenBytes(
            conversationId: conversation.id,
            creatorInboxId: conversation.inboxId,
            secp256k1PrivateKey: privateKey
        )
        var payload = InvitePayload()
        if let name = conversation.name {
            payload.name = name
        }
        if let description_p = conversation.description {
            payload.description_p = description_p
        }
        if let imageURL = conversation.imageURLString {
            payload.imageURL = imageURL
        }
        if let conversationExpiresAt = conversation.expiresAt {
            payload.conversationExpiresAtUnix = Int64(conversationExpiresAt.timeIntervalSince1970)
        }
        payload.expiresAfterUse = expiresAfterUse
        payload.tag = conversation.inviteTag
        payload.conversationToken = conversationTokenBytes
        payload.creatorInboxID = conversation.inboxId
        if let expiresAt {
            payload.expiresAtUnix = Int64(expiresAt.timeIntervalSince1970)
        }
        let signature = try payload.sign(with: privateKey)
        var signedInvite = SignedInvite()
        signedInvite.payload = payload
        signedInvite.signature = signature
        return try signedInvite.toURLSafeSlug()
    }
}

extension InvitePayload {
    public var expiresAtUnixIfPresent: Date? {
        guard hasExpiresAtUnix else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(expiresAtUnix))
    }

    public var conversationExpiresAtUnixIfPresent: Date? {
        guard hasConversationExpiresAtUnix else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(conversationExpiresAtUnix))
    }

    public var nameIfPresent: String? {
        guard hasName else { return nil }
        return name
    }

    public var descriptionIfPresent: String? {
        guard hasDescription_p else { return nil }
        return description_p
    }

    public var imageURLIfPresent: String? {
        guard hasImageURL else { return nil }
        return imageURL
    }
}

// MARK: - Signing

enum EncodableSignatureError: Error {
    case invalidContext
    case signatureFailure
    case encodingFailure
    case invalidSignature
    case invalidPublicKey
    case invalidPrivateKey
    case verificationFailure
    case invalidFormat
}

extension InvitePayload {
    func sign(with privateKey: Data) throws -> Data {
        // Validate private key length to prevent out-of-bounds reads
        guard privateKey.count == 32 else {
            throw EncodableSignatureError.invalidPrivateKey
        }

        guard let ctx = secp256k1_context_create(
            UInt32(SECP256K1_CONTEXT_SIGN | SECP256K1_CONTEXT_VERIFY)
        ) else {
            throw EncodableSignatureError.invalidContext
        }

        defer {
            secp256k1_context_destroy(ctx)
        }

        // Hash the message using SHA256
        let messageHash = try serializedData().sha256Hash()

        let signaturePtr = UnsafeMutablePointer<secp256k1_ecdsa_recoverable_signature>.allocate(capacity: 1)
        defer {
            signaturePtr.deallocate()
        }

        // Use withUnsafeBytes to ensure pointer lifetime is valid during C API call
        let result = messageHash.withUnsafeBytes { msgBuffer -> Int32 in
            guard let msg = msgBuffer.bindMemory(to: UInt8.self).baseAddress else {
                return 0
            }
            return privateKey.withUnsafeBytes { keyBuffer -> Int32 in
                guard let privateKeyPtr = keyBuffer.bindMemory(to: UInt8.self).baseAddress else {
                    return 0
                }
                return secp256k1_ecdsa_sign_recoverable(
                    ctx, signaturePtr, msg, privateKeyPtr, nil, nil
                )
            }
        }

        guard result == 1 else {
            throw EncodableSignatureError.signatureFailure
        }

        let outputPtr = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
        defer {
            outputPtr.deallocate()
        }

        var recid: Int32 = 0
        guard secp256k1_ecdsa_recoverable_signature_serialize_compact(
            ctx, outputPtr, &recid, signaturePtr
        ) == 1 else {
            throw EncodableSignatureError.encodingFailure
        }

        // Combine signature and recovery ID
        let outputWithRecidPtr = UnsafeMutablePointer<UInt8>.allocate(capacity: 65)
        defer {
            outputWithRecidPtr.deallocate()
        }

        outputWithRecidPtr.update(from: outputPtr, count: 64)
        outputWithRecidPtr.advanced(by: 64).pointee = UInt8(recid)

        return Data(bytes: outputWithRecidPtr, count: 65)
    }
}

// MARK: - URL-safe Base64 encoding

extension SignedInvite {
    /// Magic byte to identify compressed vs uncompressed data
    internal static let compressionMarker: UInt8 = 0x1F  // GZIP-like marker

    /// Maximum allowed decompressed size (1 MB) to prevent decompression bombs
    private static let maxDecompressedSize: UInt32 = 1 * 1024 * 1024

    /// Encode to URL-safe base64 string with optional compression
    public func toURLSafeSlug() throws -> String {
        let protobufData = try self.serializedData()

        // Invites are typically >100 bytes (signature alone is 65), so try compression
        let data: Data
        if let compressed = protobufData.compressedWithSize() {
            // Only use compression if it actually saves space
            if compressed.count < protobufData.count {
                data = compressed
            } else {
                data = protobufData
            }
        } else {
            data = protobufData
        }

        return data.base64URLEncoded()
    }

    /// Decode from URL-safe base64 string with automatic decompression
    public static func fromURLSafeSlug(_ slug: String) throws -> SignedInvite {
        let data = try slug.base64URLDecoded()

        // Check if data is compressed by looking at the first byte
        let protobufData: Data
        if data.first == compressionMarker {
            // Data format: [marker: 1 byte][size: 4 bytes][compressed data]
            guard let decompressed = data.decompressedWithSize(maxSize: maxDecompressedSize) else {
                throw EncodableSignatureError.invalidFormat
            }
            protobufData = decompressed
        } else {
            protobufData = data
        }

        return try SignedInvite(serializedBytes: protobufData)
    }

    /// Decode from either the full URL string or the invite code string
    public static func fromInviteCode(_ code: String) throws -> SignedInvite {
        // Trim whitespace and newlines from input to handle padded URLs
        let trimmedInput = code.trimmingCharacters(in: .whitespacesAndNewlines)

        let extractedCode: String
        if let url = URL(string: trimmedInput),
           let codeFromURL = url.convosInviteCode {
            // Use the URL extension which handles both v2 query params and app scheme
            extractedCode = codeFromURL
        } else {
            // If URL parsing fails, treat the input as a raw invite code
            extractedCode = trimmedInput
        }

        // Trim again in case the extracted code has whitespace
        let finalCode = extractedCode.trimmingCharacters(in: .whitespacesAndNewlines)
        return try fromURLSafeSlug(finalCode)
    }
}

// MARK: - Signature Validation

extension SignedInvite {
    func verify(with expectedPublicKey: Data) throws -> Bool {
        // Recover the public key from the signature using this data as the message
        let recoveredPublicKey = try recoverSignerPublicKey()

        // Compare the recovered key with the expected key
        // If the expected key is uncompressed (65 bytes) and recovered is compressed (33 bytes),
        // or vice versa, we need to handle the comparison properly
        if recoveredPublicKey.count == expectedPublicKey.count {
            return recoveredPublicKey == expectedPublicKey
        } else {
            // Convert both to the same format for comparison
            let normalizedRecovered = try recoveredPublicKey.normalizePublicKey()
            let normalizedExpected = try expectedPublicKey.normalizePublicKey()
            return normalizedRecovered == normalizedExpected
        }
    }

    public func recoverSignerPublicKey() throws -> Data {
        guard signature.count == 65 else {
            throw EncodableSignatureError.invalidSignature
        }

        guard let ctx = secp256k1_context_create(
            UInt32(SECP256K1_CONTEXT_SIGN | SECP256K1_CONTEXT_VERIFY)
        ) else {
            throw EncodableSignatureError.invalidContext
        }

        defer {
            secp256k1_context_destroy(ctx)
        }

        // Hash the message
        let messageHash = try payload.serializedData().sha256Hash()

        // Extract signature and recovery ID from the signature parameter
        let signatureData = signature.prefix(64)
        let recid = Int32(signature[64])

        // Parse the recoverable signature
        var recoverableSignature = secp256k1_ecdsa_recoverable_signature()

        // Use withUnsafeBytes to ensure pointer lifetime is valid during C API call
        let parseResult = signatureData.withUnsafeBytes { sigBuffer -> Int32 in
            guard let signaturePtr = sigBuffer.bindMemory(to: UInt8.self).baseAddress else {
                return 0
            }
            return secp256k1_ecdsa_recoverable_signature_parse_compact(
                ctx, &recoverableSignature, signaturePtr, recid
            )
        }

        guard parseResult == 1 else {
            throw EncodableSignatureError.invalidSignature
        }

        // Recover the public key
        var pubkey = secp256k1_pubkey()

        let recoverResult = messageHash.withUnsafeBytes { msgBuffer -> Int32 in
            guard let msgPtr = msgBuffer.bindMemory(to: UInt8.self).baseAddress else {
                return 0
            }
            return secp256k1_ecdsa_recover(ctx, &pubkey, &recoverableSignature, msgPtr)
        }

        guard recoverResult == 1 else {
            throw EncodableSignatureError.verificationFailure
        }

        // Serialize the public key (uncompressed format)
        let outputPtr = UnsafeMutablePointer<UInt8>.allocate(capacity: 65)
        defer { outputPtr.deallocate() }

        var outputLen = 65
        guard secp256k1_ec_pubkey_serialize(
            ctx,
            outputPtr,
            &outputLen,
            &pubkey,
            UInt32(SECP256K1_EC_UNCOMPRESSED)
        ) == 1 else {
            throw EncodableSignatureError.verificationFailure
        }

        return Data(bytes: outputPtr, count: outputLen)
    }
}

extension Data {
    /// Normalizes a public key to compressed format for comparison
    func normalizePublicKey() throws -> Data {
        guard let ctx = secp256k1_context_create(
            UInt32(SECP256K1_CONTEXT_SIGN | SECP256K1_CONTEXT_VERIFY)
        ) else {
            throw EncodableSignatureError.invalidContext
        }

        defer {
            secp256k1_context_destroy(ctx)
        }

        // Parse the public key
        var pubkey = secp256k1_pubkey()

        // Use withUnsafeBytes to ensure pointer lifetime is valid during C API call
        let parseResult = self.withUnsafeBytes { buffer -> Int32 in
            guard let publicKeyPtr = buffer.bindMemory(to: UInt8.self).baseAddress else {
                return 0
            }
            return secp256k1_ec_pubkey_parse(ctx, &pubkey, publicKeyPtr, self.count)
        }

        guard parseResult == 1 else {
            throw EncodableSignatureError.invalidPublicKey
        }

        // Serialize to compressed format
        let outputPtr = UnsafeMutablePointer<UInt8>.allocate(capacity: 33)
        defer {
            outputPtr.deallocate()
        }

        var outputLen = 33
        guard secp256k1_ec_pubkey_serialize(
            ctx, outputPtr, &outputLen, &pubkey,
            UInt32(SECP256K1_EC_COMPRESSED)
        ) == 1 else {
            throw EncodableSignatureError.invalidPublicKey
        }

        return Data(bytes: outputPtr, count: outputLen)
    }

    /// Computes SHA256 hash of this data
    func sha256Hash() -> Data {
        let hash = SHA256.hash(data: self)
        return Data(hash)
    }
}

// MARK: - Compression Helpers

private extension Data {
    /// Compress data using zlib deflate and prepend format metadata
    /// Format: [marker: 1 byte][original size: 4 bytes big-endian][compressed data]
    func compressedWithSize() -> Data? {
        return self.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return nil }

            let sourceBuffer = UnsafeBufferPointer<UInt8>(
                start: baseAddress.assumingMemoryBound(to: UInt8.self),
                count: count
            )

            let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: count)
            defer { destinationBuffer.deallocate() }

            guard let baseAddress = sourceBuffer.baseAddress else { return nil }

            let compressedSize = compression_encode_buffer(
                destinationBuffer, count,
                baseAddress, count,
                nil, COMPRESSION_ZLIB
            )

            guard compressedSize > 0 else { return nil }

            // Build the final data: [marker][size][compressed]
            var result = Data()
            result.append(SignedInvite.compressionMarker)

            // Store original size as UInt32 big-endian (4 bytes)
            let size = UInt32(count)
            result.append(contentsOf: [
                UInt8((size >> 24) & 0xFF),
                UInt8((size >> 16) & 0xFF),
                UInt8((size >> 8) & 0xFF),
                UInt8(size & 0xFF)
            ])

            // Append compressed data
            result.append(Data(bytes: destinationBuffer, count: compressedSize))

            return result
        }
    }

    /// Decompress data using zlib inflate with size metadata
    /// Expected format: [marker: 1 byte][original size: 4 bytes big-endian][compressed data]
    /// - Parameter maxSize: Maximum allowed decompressed size (safety limit)
    /// - Returns: Decompressed data or nil if decompression fails or exceeds maxSize
    func decompressedWithSize(maxSize: UInt32) -> Data? {
        // Expected format: [marker][size: 4 bytes][compressed data]
        // Minimum: 1 (marker) + 4 (size) + 1 (data) = 6 bytes
        guard count >= 6 else { return nil }

        // Skip marker byte (already checked by caller)
        let dataAfterMarker = self.dropFirst()

        // Read original size (4 bytes, big-endian)
        guard dataAfterMarker.count >= 4 else { return nil }
        let sizeBytes = Array(dataAfterMarker.prefix(4))

        // Manually construct UInt32 from bytes to avoid alignment issues
        let originalSize: UInt32 = (UInt32(sizeBytes[0]) << 24) |
                                    (UInt32(sizeBytes[1]) << 16) |
                                    (UInt32(sizeBytes[2]) << 8) |
                                     UInt32(sizeBytes[3])
        // Security check: reject if original size exceeds maximum
        guard originalSize > 0, originalSize <= maxSize else { return nil }

        // Get compressed data (everything after size bytes)
        let compressedData = dataAfterMarker.dropFirst(4)
        guard !compressedData.isEmpty else { return nil }

        // Decompress with exact buffer size
        return compressedData.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return nil }

            let sourceBuffer = UnsafeBufferPointer<UInt8>(
                start: baseAddress.assumingMemoryBound(to: UInt8.self),
                count: compressedData.count
            )

            guard let sourceBaseAddress = sourceBuffer.baseAddress else { return nil }

            // Allocate exactly the size we expect
            let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: Int(originalSize))
            defer { destinationBuffer.deallocate() }

            let decompressedSize = compression_decode_buffer(
                destinationBuffer, Int(originalSize),
                sourceBaseAddress, compressedData.count,
                nil, COMPRESSION_ZLIB
            )

            // Verify decompression succeeded and matches expected size
            guard decompressedSize > 0, decompressedSize == Int(originalSize) else {
                return nil
            }

            return Data(bytes: destinationBuffer, count: decompressedSize)
        }
    }
}
