import Foundation
import LocalAuthentication
import Security
import XMTPiOS

struct SecureEnclaveIdentity {
    let privateKey: PrivateKey
    let databaseKey: Data
}

final class SecureEnclaveIdentityStore {
    private let keychainAccount: String = "com.convos.ios.SecureEnclaveIdentityStore.databaseKey"
    private let keychainService: String = "com.convos.ios.SecureEnclaveIdentityStore"
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
        let databaseKey = try generateAndSaveDatabaseKey()
        return SecureEnclaveIdentity(privateKey: privateKey, databaseKey: databaseKey)
    }

    func load() throws -> SecureEnclaveIdentity? {
        guard let databaseKey = try loadDatabaseKey() else {
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

    private func generateAndSaveDatabaseKey() throws -> Data {
        let databaseKey = Data((0..<32).map { _ in UInt8.random(in: UInt8.min...UInt8.max) })
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainAccount,
            kSecAttrService as String: keychainService,
            kSecValueData as String: databaseKey,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SecureEnclaveUserStoreError.failedSavingDatabaseKey
        }
        return databaseKey
    }

    private func loadDatabaseKey() throws -> Data? {
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
        guard status == errSecSuccess, let data = item as? Data else {
            throw SecureEnclaveUserStoreError.failedRetrievingDatabaseKey
        }

        return data
    }

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
