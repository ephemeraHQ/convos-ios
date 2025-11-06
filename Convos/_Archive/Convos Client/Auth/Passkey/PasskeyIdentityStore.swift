import CryptoKit
import Foundation
import Security
import SwiftCBOR

extension String {
    func base64URLToBase64() -> Data? {
        var base64 = self
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let rem = base64.count % 4
        if rem == 2 {
            base64 += "=="
        } else if rem == 3 {
            base64 += "="
        } else if rem == 1 {
            return nil
        }

        return Data(base64Encoded: base64)
    }
}

extension Data {
    func coseToSec1PublicKey() -> Data? {
        guard let decoded = try? CBORDecoder(input: bytes).decodeItem() else {
            Log.info("Failed to decode CBOR")
            return nil
        }

        let coseMap: [CBOR: CBOR]?

        switch decoded {
        case CBOR.map(let map):
            coseMap = map

        case CBOR.tagged(_, let tagged):
            if case CBOR.map(let map) = tagged {
                coseMap = map
            } else {
                coseMap = nil
            }

        case CBOR.array(let array):
            if array.count == 1, case CBOR.map(let map) = array[0] {
                coseMap = map
            } else {
                coseMap = nil
            }

        default:
            coseMap = nil
        }

        guard let map = coseMap else {
            Log.info("COSE structure is not a valid map")
            return nil
        }

        let xLabel = CBOR.negativeInt(1)
        let yLabel = CBOR.negativeInt(2)

        guard let xVal = map[xLabel], let yVal = map[yLabel],
              case let CBOR.byteString(xBytes) = xVal,
              case let CBOR.byteString(yBytes) = yVal,
              xBytes.count == 32, yBytes.count == 32 else {
            Log.info("Missing or invalid x/y values")
            return nil
        }

        var sec1 = Data([0x04])
        sec1.append(contentsOf: xBytes)
        sec1.append(contentsOf: yBytes)
        return sec1
    }
}

struct PasskeyIdentity: Codable {
    enum PasskeyIdentityError: Error {
        case failedGeneratingDatabaseKey
    }

    let credentialID: Data
    let publicKey: Data
    let userID: String
    let databaseKey: Data

    static func generateSecureDatabaseKey() throws -> Data {
        return Data((0 ..< 32)
            .map { _ in UInt8.random(in: UInt8.min ... UInt8.max) })
    }
}

final class PasskeyIdentityStore {
    private let keychainAccount: String = "com.convos.ios.PasskeyUserStore.identity"
    private let keychainService: String = "com.convos.ios.PasskeyUserStore"

    enum PasskeyUserStoreError: Error {
        case failedRetrievingIdentity
        case failedDeletingIdentity
        case failedSavingIdentity
        case failedEncodingIdentity
        case failedDecodingIdentity
        case failedRetrievingPrivateKey
        case failedExtractingPublicKey
    }

    func save(credentialID: Data, publicKey: String, userID: String) throws -> PasskeyIdentity {
        guard let publicKeyBase64 = publicKey.base64URLToBase64(),
              let publicKey = publicKeyBase64.coseToSec1PublicKey() else {
            throw PasskeyUserStoreError.failedExtractingPublicKey
        }
        let databaseKey = try PasskeyIdentity.generateSecureDatabaseKey()
        let identity = PasskeyIdentity(credentialID: credentialID,
                                       publicKey: publicKey,
                                       userID: userID,
                                       databaseKey: databaseKey)

        let encoder = JSONEncoder()
        let data = try encoder.encode(identity)

        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainAccount,
            kSecAttrService as String: keychainService
        ]
        let deleteStatus = SecItemDelete(deleteQuery as CFDictionary)
        guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
            throw PasskeyUserStoreError.failedDeletingIdentity
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainAccount,
            kSecAttrService as String: keychainService,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw PasskeyUserStoreError.failedSavingIdentity
        }

        return identity
    }

    func load() throws -> PasskeyIdentity? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainAccount,
            kSecAttrService as String: keychainService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status != errSecItemNotFound else { return nil }
        guard status == errSecSuccess else {
            throw PasskeyUserStoreError.failedRetrievingIdentity
        }

        guard let data = item as? Data else {
            return nil
        }

        let decoder = JSONDecoder()
        return try decoder.decode(PasskeyIdentity.self, from: data)
    }

    func delete() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainAccount,
            kSecAttrService as String: keychainService
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw PasskeyUserStoreError.failedDeletingIdentity
        }
    }
}
