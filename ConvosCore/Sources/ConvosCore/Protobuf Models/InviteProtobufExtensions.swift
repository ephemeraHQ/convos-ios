import CryptoKit
import CSecp256k1
import Foundation
import SwiftProtobuf

extension SignedInvite {
    public var expiresAt: Date? {
        payload.expiresAtIfPresent
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
        payload.conversationExpiresAtIfPresent
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
        let conversationToken = try InviteConversationToken.makeConversationToken(
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
            payload.conversationExpiresAt = .init(date: conversationExpiresAt)
        }
        payload.expiresAfterUse = expiresAfterUse
        payload.tag = conversation.inviteTag
        payload.conversationToken = conversationToken
        payload.creatorInboxID = conversation.inboxId
        payload.expiresAtIfPresent = expiresAt
        let signature = try payload.sign(with: privateKey)
        var signedInvite = SignedInvite()
        signedInvite.payload = payload
        signedInvite.signature = signature
        return try signedInvite.toURLSafeSlug()
    }
}

extension InvitePayload {
    public var expiresAtIfPresent: Date? {
        get {
            guard hasExpiresAt else { return nil }
            return expiresAt.date
        }
        set {
            if let newValue {
                expiresAt = .init(date: newValue)
            } else {
                clearExpiresAt()
            }
        }
    }

    public var conversationExpiresAtIfPresent: Date? {
        guard hasConversationExpiresAt else { return nil }
        return conversationExpiresAt.date
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
    /// Encode to URL-safe base64 string
    public func toURLSafeSlug() throws -> String {
        let data = try self.serializedData()
        return data.base64URLEncoded()
    }

    /// Decode from URL-safe base64 string
    public static func fromURLSafeSlug(_ slug: String) throws -> SignedInvite {
        let data = try slug.base64URLDecoded()
        return try SignedInvite(serializedBytes: data)
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
