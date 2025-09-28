import CryptoKit
import CSecp256k1
import Foundation
import SwiftProtobuf

extension SignedInvite {
    public static func slug(for conversation: DBConversation, privateKey: Data) throws -> String {
        let code = try InviteCode.makeCode(
            conversationId: conversation.id,
            creatorInboxId: conversation.inboxId,
            secp256k1PrivateKey: privateKey
        )
        var payload = InvitePayload()
        payload.tag = try InviteTag.generate(for: conversation.id)
        payload.code = code
        payload.creatorInboxID = conversation.inboxId
        let signature = try payload.sign(with: privateKey)
        var signedInvite = SignedInvite()
        signedInvite.payload = payload
        signedInvite.signature = signature
        return try signedInvite.toURLSafeSlug()
    }
}

// MARK: - Tag Generation

enum InviteTagError: Error {
    case randomGenerationFailed
    case encodingFailed
}

extension InviteTag {
    /// Generate a tag for the given conversationId with a fresh random nonce.
    public static func generate(for conversationId: String) throws -> Self {
        // Make a 16-byte random nonce
        var nonceBytes = [UInt8](repeating: 0, count: 16)
        let rc = SecRandomCopyBytes(kSecRandomDefault, nonceBytes.count, &nonceBytes)
        guard rc == errSecSuccess else {
            throw InviteTagError.randomGenerationFailed
        }

        let nonce = Data(nonceBytes)
        let message = nonce + Data(conversationId.utf8)
        let hash = SHA256.hash(data: message)

        var tag = InviteTag()
        tag.nonce = nonce
        tag.value = Data(hash)
        return tag
    }

    /// Check if this tag corresponds to the provided conversationId.
    public func matches(conversationId: String) -> Bool {
        let message = self.nonce + Data(conversationId.utf8)
        let expected = SHA256.hash(data: message)
        return Data(expected) == self.value
    }
}
// MARK: - Signing

enum EncodableSignatureError: Error {
    case invalidContext
    case signatureFailure
    case encodingFailure
    case invalidSignature
    case invalidPublicKey
    case verificationFailure
}

extension InvitePayload {
    func sign(with privateKey: Data) throws -> Data {
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

        let msg = (messageHash as NSData).bytes.assumingMemoryBound(to: UInt8.self)
        let privateKeyPtr = (privateKey as NSData).bytes.assumingMemoryBound(to: UInt8.self)

        let signaturePtr = UnsafeMutablePointer<secp256k1_ecdsa_recoverable_signature>.allocate(capacity: 1)
        defer {
            signaturePtr.deallocate()
        }

        guard secp256k1_ecdsa_sign_recoverable(
            ctx, signaturePtr, msg, privateKeyPtr, nil, nil
        ) == 1 else {
            throw EncodableSignatureError.signatureFailure
        }

        let outputPtr = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
        defer {
            outputPtr.deallocate()
        }

        var recid: Int32 = 0
        secp256k1_ecdsa_recoverable_signature_serialize_compact(
            ctx, outputPtr, &recid, signaturePtr
        )

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
    /// Encode to URL-safe base64 string (similar to InviteSlugComposer.slug)
    public func toURLSafeSlug() throws -> String {
        let data = try self.serializedData()
        return data.base64URLEncoded()
    }

    /// Decode from URL-safe base64 string (similar to InviteSlugComposer.decode)
    public static func fromURLSafeSlug(_ slug: String) throws -> SignedInvite {
        let data = try slug.base64URLDecoded()
        return try SignedInvite(serializedBytes: data)
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
        let signaturePtr = (signatureData as NSData).bytes.assumingMemoryBound(to: UInt8.self)

        guard secp256k1_ecdsa_recoverable_signature_parse_compact(
            ctx, &recoverableSignature, signaturePtr, recid
        ) == 1 else {
            throw EncodableSignatureError.invalidSignature
        }

        // Recover the public key
        var pubkey = secp256k1_pubkey()
        let msgPtr = (messageHash as NSData).bytes.assumingMemoryBound(to: UInt8.self)

        guard secp256k1_ecdsa_recover(ctx, &pubkey, &recoverableSignature, msgPtr) == 1 else {
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
        let publicKeyPtr = (self as NSData).bytes.assumingMemoryBound(to: UInt8.self)

        guard secp256k1_ec_pubkey_parse(ctx, &pubkey, publicKeyPtr, self.count) == 1 else {
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
