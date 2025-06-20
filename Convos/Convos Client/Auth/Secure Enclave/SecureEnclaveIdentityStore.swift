import Foundation
import LocalAuthentication
import Security
import XMTPiOS

struct SecureEnclaveIdentity {
    let privateKey: PrivateKey
    let databaseKey: Data
}

protocol SecureEnclaveKeyStore {
    func generateAndSaveDatabaseKey(for identifier: String) throws -> Data
    func loadDatabaseKey(for identifier: String) throws -> Data?

    var keychainService: String { get }
}

enum SecureEnclaveKeyStoreError: Error {
    case failedRetrievingDatabaseKey,
         failedDeletingDatabaseKey,
         failedSavingDatabaseKey,
         failedGeneratingDatabaseKey
}

extension SecureEnclaveKeyStore {
    func generateAndSaveDatabaseKey(for identifier: String) throws -> Data {
        let databaseKey = Data((0..<32).map { _ in UInt8.random(in: UInt8.min...UInt8.max) })
        return try saveDatabaseKey(databaseKey, for: identifier)
    }

    func saveDatabaseKey(_ databaseKey: Data, for identifier: String) throws -> Data {
        let identifier = identifier.lowercased()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: identifier,
            kSecAttrService as String: keychainService,
            kSecValueData as String: databaseKey,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            Logger.info("Database key found for identifier: \(identifier), overwriting...")
            let attributesToUpdate: [String: Any] = [
                kSecValueData as String: databaseKey
            ]
            var updateQuery = query
            updateQuery.removeValue(forKey: kSecValueData as String)
            let updateStatus = SecItemUpdate(updateQuery as CFDictionary, attributesToUpdate as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw SecureEnclaveKeyStoreError.failedSavingDatabaseKey
            }
        }
        return databaseKey
    }

    func loadDatabaseKey(for identifier: String) throws -> Data? {
        let identifier = identifier.lowercased()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: identifier,
            kSecAttrService as String: keychainService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status != errSecItemNotFound else { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw SecureEnclaveKeyStoreError.failedRetrievingDatabaseKey
        }

        return data
    }
}

final class SecureEnclaveIdentityStore: SecureEnclaveKeyStore {
    private let keychainAccount: String = "com.convos.ios.SecureEnclaveIdentityStore.databaseKey"
    internal let keychainService: String = "com.convos.ios.SecureEnclaveIdentityStore"
    private let keyTagString: String = "com.convos.ios.SecureEnclaveIdentityStore.secp256k1"

    enum SecureEnclaveUserStoreError: Error {
        case failedRetrievingDatabaseKey,
             failedDeletingDatabaseKey,
             failedSavingDatabaseKey,
             failedGeneratingDatabaseKey,
             keyTagMismatch,
             biometryAuthFailed,
             privateKeyNotFound,
             failedGeneratingPrivateKey
    }

    func save() throws -> SecureEnclaveIdentity {
        let privateKey = try generatePrivateKeyWithBiometry()
        let databaseKey = try generateAndSaveDatabaseKey(for: keychainAccount)
        return SecureEnclaveIdentity(privateKey: privateKey, databaseKey: databaseKey)
    }

    func load() throws -> SecureEnclaveIdentity? {
        guard let databaseKey = try loadDatabaseKey(for: keychainAccount) else {
            return nil
        }

        let privateKey = try loadPrivateKeyWithBiometry()
        return SecureEnclaveIdentity(privateKey: privateKey, databaseKey: databaseKey)
    }

    func delete() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainAccount,
            kSecAttrService as String: keychainService
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecureEnclaveUserStoreError.failedDeletingDatabaseKey
        }
    }

    // MARK: - Private Helpers

    private func generatePrivateKeyWithBiometry() throws -> PrivateKey {
        guard let keyTag = keyTagString.data(using: .utf8) else {
            throw SecureEnclaveUserStoreError.keyTagMismatch
        }

        let privateKey = try PrivateKey.generate()

        guard let accessControl = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            [.userPresence],
            nil
        ) else {
            throw SecureEnclaveUserStoreError.failedGeneratingPrivateKey
        }

        let attributes: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: keyTag,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecValueData as String: privateKey.secp256K1.bytes,
            kSecAttrAccessControl as String: accessControl
        ]

        SecItemDelete(attributes as CFDictionary)

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SecureEnclaveUserStoreError.failedGeneratingPrivateKey
        }

        return privateKey
    }

    private func loadPrivateKeyWithBiometry() throws -> PrivateKey {
        guard let keyTag = keyTagString.data(using: .utf8) else {
            throw SecureEnclaveUserStoreError.keyTagMismatch
        }

        let context = LAContext()
        context.localizedReason = "Authenticate to access Convos"
        context.interactionNotAllowed = false

        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: keyTag,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecReturnData as String: true,
            kSecUseAuthenticationContext as String: context
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            throw SecureEnclaveUserStoreError.privateKeyNotFound
        }

        return try PrivateKey(data)
    }
}
