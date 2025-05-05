import Foundation
import Security

class KeyGenerator {
    struct KeyPair {
        let privateKey: SecKey
        let publicKey: SecKey
        let publicKeyCompressed: Data
        let publicKeyUncompressed: Data

        var publicKeyString: String {
            publicKeyCompressed.base64EncodedString()
        }
    }

    enum KeyGenerationError: Error {
        case keyGenerationFailed
        case publicKeyExtractionFailed
        case invalidKeyFormat
    }

    static func generateP256KeyPair() throws -> KeyPair {
        // Key generation parameters
        let parameters: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: false
            ]
        ]

        // Generate key pair
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(parameters as CFDictionary, &error),
              let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw KeyGenerationError.keyGenerationFailed
        }

        // Extract public key data
        var error2: Unmanaged<CFError>?
        guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, &error2) as Data? else {
            throw KeyGenerationError.publicKeyExtractionFailed
        }

        // Convert to compressed and uncompressed formats
        let uncompressedData = publicKeyData
        let compressedData = try compressPublicKey(uncompressedData)

        return KeyPair(
            privateKey: privateKey,
            publicKey: publicKey,
            publicKeyCompressed: compressedData,
            publicKeyUncompressed: uncompressedData
        )
    }

    enum PublicKeyCompressionError: Error {
        case invalidKeyLength
        case invalidYComponent
    }

    static func compressPublicKey(_ uncompressedKey: Data) throws -> Data {
        // P-256 public key is 65 bytes in uncompressed form (0x04 || x || y)
        // Compressed form is 33 bytes (0x02/0x03 || x)

        // Validate input length
        guard uncompressedKey.count == 65 else {
            throw PublicKeyCompressionError.invalidKeyLength
        }

        let x = uncompressedKey.subdata(in: 1..<33)
        let y = uncompressedKey.subdata(in: 33..<65)

        // Safely get last byte of y
        guard let lastByte = y.last else {
            throw PublicKeyCompressionError.invalidYComponent
        }

        // Check if y is even or odd
        let prefix: UInt8 = (lastByte & 0x01) == 0 ? 0x02 : 0x03

        var compressed = Data()
        compressed.append(prefix)
        compressed.append(x)

        return compressed
    }
}
