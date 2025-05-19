import Foundation
import Security

extension String {
    func base64URLToBase64() -> Data? {
        var base64 = self
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let padding = 4 - base64.count % 4
        if padding < 4 {
            base64 += String(repeating: "=", count: padding)
        }

        return Data(base64Encoded: base64)
    }
}

extension Data {
    func coseToSec1PublicKey() -> Data? {
        // Remove overly strict length check
        // Find the X and Y coordinates in the COSE key
        guard let xRange = self.range(of: Data([0x21, 0x58, 0x20])),
              let yRange = self.range(of: Data([0x22, 0x58, 0x20])) else {
            return nil
        }

        let xStart = xRange.upperBound
        let yStart = yRange.upperBound

        guard xStart + 32 <= self.count, yStart + 32 <= self.count else {
            return nil
        }

        let x = self[xStart..<xStart+32]
        let y = self[yStart..<yStart+32]

        var sec1 = Data([0x04])
        sec1.append(x)
        sec1.append(y)
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
