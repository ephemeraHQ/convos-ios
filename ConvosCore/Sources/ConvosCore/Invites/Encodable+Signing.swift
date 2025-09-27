import CryptoKit
import CSecp256k1
import Foundation

// MARK: - Errors

enum EncodableSignatureError: Error {
    case invalidContext
    case signatureFailure
    case encodingFailure
    case invalidSignature
    case invalidPublicKey
    case verificationFailure
}

// MARK: - Encodable Extension

extension Encodable {
    // MARK: - Instance Methods for Signing

    /// Signs this encodable object using the provided private key
    /// - Parameter privateKey: The private key to use for signing
    /// - Returns: The signature data (65 bytes: 64 bytes signature + 1 byte recovery ID)
    func sign(with privateKey: Data) throws -> Data {
        // Encode self to Data
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys // Ensure consistent encoding

        let data: Data
        do {
            data = try encoder.encode(self)
        } catch {
            throw EncodableSignatureError.encodingFailure
        }

        return try data.signWithPrivateKey(privateKey)
    }

    /// Verifies a signature for this encodable object using the provided public key
    /// - Parameters:
    ///   - signature: The signature to verify (65 bytes)
    ///   - publicKey: The public key to use for verification
    /// - Returns: True if the signature is valid, false otherwise
    func verify(signature: Data, with publicKey: Data) throws -> Bool {
        // Encode self to Data
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys // Ensure consistent encoding

        let data: Data
        do {
            data = try encoder.encode(self)
        } catch {
            throw EncodableSignatureError.encodingFailure
        }

        return try data.verifySignature(signature, with: publicKey)
    }

    /// Recovers the public key that created this signature
    /// - Parameter signature: The signature in (r, s, v) format (65 bytes)
    /// - Returns: The recovered public key (compressed format, 33 bytes)
    func recoverSignerPublicKey(from signature: Data) throws -> Data {
        // Encode self to Data
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys

        let data: Data
        do {
            data = try encoder.encode(self)
        } catch {
            throw EncodableSignatureError.encodingFailure
        }

        return try data.recoverPublicKey(from: signature)
    }

    /// Verifies that this signature was created by the expected public key
    /// - Parameters:
    ///   - signature: The signature in (r, s, v) format (65 bytes)
    ///   - expectedPublicKey: The expected public key to verify against
    /// - Returns: True if the signature was created by the expected public key
    func verifySignatureFromExpectedSigner(signature: Data, expectedPublicKey: Data) throws -> Bool {
        // Encode self to Data
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys

        let data: Data
        do {
            data = try encoder.encode(self)
        } catch {
            throw EncodableSignatureError.encodingFailure
        }

        return try data.verifySignatureWithRecovery(signature, expectedPublicKey: expectedPublicKey)
    }

    /// Recovers the public key from r, s, v signature components
    /// - Parameters:
    ///   - r: The r component of the signature (32 bytes)
    ///   - s: The s component of the signature (32 bytes)
    ///   - v: The recovery ID (0-3, or 27-30 for Ethereum compatibility)
    /// - Returns: The recovered public key (compressed format, 33 bytes)
    func recoverSignerPublicKeyFromRSV(r: Data, s: Data, v: UInt8) throws -> Data {
        // Combine r, s, and v into a single signature
        var signature = Data()
        signature.append(r)
        signature.append(s)
        // Normalize v to 0-3 range (handle Ethereum's 27-30 format)
        let recid = v >= 27 ? v - 27 : v
        guard recid <= 3 else {
            throw EncodableSignatureError.invalidSignature
        }
        signature.append(recid)

        return try recoverSignerPublicKey(from: signature)
    }

    /// Verifies this encodable object was signed by the expected public key using r, s, v components
    /// - Parameters:
    ///   - r: The r component of the signature (32 bytes)
    ///   - s: The s component of the signature (32 bytes)
    ///   - v: The recovery ID (0-3, or 27-30 for Ethereum compatibility)
    ///   - expectedPublicKey: The expected public key to verify against
    /// - Returns: True if the signature was created by the expected public key
    func verifySignatureFromExpectedSignerWithRSV(r: Data, s: Data, v: UInt8, expectedPublicKey: Data) throws -> Bool {
        // Encode self to Data
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys

        let data: Data
        do {
            data = try encoder.encode(self)
        } catch {
            throw EncodableSignatureError.encodingFailure
        }

        return try data.verifySignatureWithRSV(r: r, s: s, v: v, expectedPublicKey: expectedPublicKey)
    }
}

// MARK: - Data Extension for Cryptographic Operations

extension Data {
    // MARK: - Signing

    /// Signs this data using the provided private key
    /// - Parameter privateKey: The private key to use for signing
    /// - Returns: The signature data (65 bytes: 64 bytes signature + 1 byte recovery ID)
    func signWithPrivateKey(_ privateKey: Data) throws -> Data {
        guard let ctx = secp256k1_context_create(
            UInt32(SECP256K1_CONTEXT_SIGN | SECP256K1_CONTEXT_VERIFY)
        ) else {
            throw EncodableSignatureError.invalidContext
        }

        defer {
            secp256k1_context_destroy(ctx)
        }

        // Hash the message using SHA256
        let messageHash = self.sha256Hash()

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

    // MARK: - Verification

    /// Verifies a signature for this data using the provided public key
    /// - Parameters:
    ///   - signature: The signature to verify (65 bytes)
    ///   - publicKey: The public key to use for verification
    /// - Returns: True if the signature is valid, false otherwise
    func verifySignature(_ signature: Data, with publicKey: Data) throws -> Bool {
        guard signature.count == 65 else {
            throw EncodableSignatureError.invalidSignature
        }

        guard publicKey.count == 33 || publicKey.count == 65 else {
            throw EncodableSignatureError.invalidPublicKey
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
        let messageHash = self.sha256Hash()

        // Parse the public key
        var pubkey = secp256k1_pubkey()
        let publicKeyPtr = (publicKey as NSData).bytes.assumingMemoryBound(to: UInt8.self)

        guard secp256k1_ec_pubkey_parse(ctx, &pubkey, publicKeyPtr, publicKey.count) == 1 else {
            throw EncodableSignatureError.invalidPublicKey
        }

        // Extract signature and recovery ID
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

        // Convert to normal signature for verification
        var normalSignature = secp256k1_ecdsa_signature()
        guard secp256k1_ecdsa_recoverable_signature_convert(
            ctx, &normalSignature, &recoverableSignature
        ) == 1 else {
            throw EncodableSignatureError.invalidSignature
        }

        // Verify the signature
        let msgPtr = (messageHash as NSData).bytes.assumingMemoryBound(to: UInt8.self)
        let result = secp256k1_ecdsa_verify(ctx, &normalSignature, msgPtr, &pubkey)

        return result == 1
    }

    /// Verifies a signature by recovering the public key and comparing it to an expected key
    /// - Parameters:
    ///   - signature: The signature in (r, s, v) format (65 bytes)
    ///   - expectedPublicKey: The expected public key to compare against
    /// - Returns: True if the recovered public key matches the expected one
    func verifySignatureWithRecovery(_ signature: Data, expectedPublicKey: Data) throws -> Bool {
        // Recover the public key from the signature using this data as the message
        let recoveredPublicKey = try self.recoverPublicKey(from: signature)

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

    /// Verifies a signature using r, s, v components separately
    /// - Parameters:
    ///   - r: The r component of the signature (32 bytes)
    ///   - s: The s component of the signature (32 bytes)
    ///   - v: The recovery ID (0-3, or 27-30 for Ethereum compatibility)
    ///   - expectedPublicKey: The expected public key to compare against
    /// - Returns: True if the recovered public key matches the expected one
    func verifySignatureWithRSV(r: Data, s: Data, v: UInt8, expectedPublicKey: Data) throws -> Bool {
        guard r.count == 32 && s.count == 32 else {
            throw EncodableSignatureError.invalidSignature
        }

        // Normalize v to 0-3 range (handle Ethereum's 27-30 format)
        let recid = v >= 27 ? v - 27 : v
        guard recid <= 3 else {
            throw EncodableSignatureError.invalidSignature
        }

        // Combine r, s, and v into a single signature
        var signature = Data()
        signature.append(r)
        signature.append(s)
        signature.append(recid)

        return try self.verifySignatureWithRecovery(signature, expectedPublicKey: expectedPublicKey)
    }

    // MARK: - Key Recovery

    /// Recovers the public key from a signature for this message data
    /// - Parameter signature: The signature with recovery ID (65 bytes)
    /// - Returns: The recovered public key
    func recoverPublicKey(from signature: Data) throws -> Data {
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

        // Hash the message (self is the message data, not the signature)
        let messageHash = self.sha256Hash()

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

    // MARK: - Helper Methods

    /// Computes SHA256 hash of this data
    func sha256Hash() -> Data {
        let hash = SHA256.hash(data: self)
        return Data(hash)
    }

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
}
