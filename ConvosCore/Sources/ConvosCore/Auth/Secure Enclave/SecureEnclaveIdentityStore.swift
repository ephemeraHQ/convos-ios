import CryptoKit
import Foundation
import LocalAuthentication
import Security
import XMTPiOS

struct SecureEnclaveIdentity {
    let id: String
    let privateKey: PrivateKey
    let databaseKey: Data
    let type: InboxType
}

protocol SecureEnclaveKeyStore {
    func generateAndSaveDatabaseKey(for identifier: String) throws -> Data
    func loadDatabaseKey(for identifier: String) throws -> Data?

    var keychainService: String { get }
}

enum SecureEnclaveKeyStoreError: Error {
    case failedRetrievingDatabaseKey,
         failedRetreivingInboxType,
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
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
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
        } else if status != errSecSuccess {
            throw SecureEnclaveKeyStoreError.failedSavingDatabaseKey
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
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
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
    internal let keychainService: String = "com.convos.ios.SecureEnclaveIdentityStore"
    private let identitiesListKey: String = "com.convos.ios.SecureEnclaveIdentityStore.identitiesList"

    enum SecureEnclaveUserStoreError: Error {
        case failedRetrievingDatabaseKey,
             failedRetrievingInboxType,
             failedDeletingDatabaseKey,
             failedDeletingPrivateKey,
             failedDeletingInboxType,
             failedDeletingInboxId,
             failedSavingDatabaseKey,
             failedSavingInboxType,
             failedSavingInboxId,
             failedSavingProviderId,
             failedLoadingProviderId,
             failedGeneratingDatabaseKey,
             failedGeneratingPrivateKey,
             failedSavingPrivateKey,
             failedLoadingPrivateKey,
             failedSavingIdentitiesList,
             failedLoadingIdentitiesList,
             failedLoadingInboxId,
             rollbackFailed
    }

    func save(type: InboxType) throws -> SecureEnclaveIdentity {
        let identityId = UUID().uuidString

        let privateKey: PrivateKey
        do {
            privateKey = try PrivateKey.generate()
        } catch {
            throw SecureEnclaveUserStoreError.failedGeneratingPrivateKey
        }

        do {
            try savePrivateKey(privateKey, for: identityId)
        } catch {
            throw error
        }

        let databaseKey: Data
        do {
            databaseKey = try generateAndSaveDatabaseKey(for: identityId)
        } catch {
            // Rollback: Delete the private key
            try? deletePrivateKey(for: identityId)
            throw error
        }

        do {
            try saveInboxType(type: type, for: identityId)
        } catch {
            // Rollback: Delete private key and database key
            try? deletePrivateKey(for: identityId)
            try? deleteDatabaseKey(for: identityId)
            throw error
        }

        do {
            try addIdentityIdToList(identityId)
        } catch {
            // Rollback: Delete everything
            try? deletePrivateKey(for: identityId)
            try? deleteDatabaseKey(for: identityId)
            try? deleteInboxType(for: identityId)
            throw error
        }

        return SecureEnclaveIdentity(
            id: identityId,
            privateKey: privateKey,
            databaseKey: databaseKey,
            type: type
        )
    }

    func load(for identityId: String) throws -> SecureEnclaveIdentity? {
        guard let databaseKey = try loadDatabaseKey(for: identityId) else {
            return nil
        }

        let inboxType: InboxType = try loadInboxType(for: identityId)
        let privateKey = try loadPrivateKey(for: identityId)

        return SecureEnclaveIdentity(
            id: identityId,
            privateKey: privateKey,
            databaseKey: databaseKey,
            type: inboxType
        )
    }

    func loadAll() throws -> [SecureEnclaveIdentity] {
        let identityIds = try loadIdentitiesList()
        var identities: [SecureEnclaveIdentity] = []

        for identityId in identityIds {
            do {
                if let identity = try load(for: identityId) {
                    identities.append(identity)
                }
            } catch {
                Logger.error("Failed loading private key for identity: \(error)")
            }
        }

        return identities
    }

    func delete(for identityId: String) throws {
        try deleteInboxId(for: identityId)
        try removeIdentityIdFromList(identityId)
        try deleteInboxType(for: identityId)
        try deleteDatabaseKey(for: identityId)
        try deletePrivateKey(for: identityId)
    }

    // MARK: - Private Helpers

    private func savePrivateKey(_ privateKey: PrivateKey, for identityId: String) throws {
        let privateKeyData = privateKey.secp256K1.bytes

        // Use access control for better security (requires authentication to access)
        guard let accessControl = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            [],
            nil
        ) else {
            throw SecureEnclaveUserStoreError.failedSavingPrivateKey
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "\(identityId).privateKey",
            kSecAttrService as String: keychainService,
            kSecValueData as String: privateKeyData,
            kSecAttrAccessControl as String: accessControl
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SecureEnclaveUserStoreError.failedSavingPrivateKey
        }
    }

    private func loadPrivateKey(for identityId: String) throws -> PrivateKey {
        let context = LAContext()
        context.localizedReason = "Authenticate to access your Convos account"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "\(identityId).privateKey",
            kSecAttrService as String: keychainService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess, let data = item as? Data else {
            throw SecureEnclaveUserStoreError.failedLoadingPrivateKey
        }

        return try PrivateKey(data)
    }

    private func deletePrivateKey(for identityId: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "\(identityId).privateKey",
            kSecAttrService as String: keychainService
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SecureEnclaveUserStoreError.failedDeletingPrivateKey
        }
    }

    private func deleteDatabaseKey(for identityId: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: identityId.lowercased(),
            kSecAttrService as String: keychainService
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SecureEnclaveUserStoreError.failedDeletingDatabaseKey
        }
    }

    private func deleteInboxType(for identityId: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "\(identityId.lowercased()).inboxType",
            kSecAttrService as String: keychainService
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SecureEnclaveUserStoreError.failedDeletingInboxType
        }
    }

    private func loadIdentitiesList() throws -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: identitiesListKey,
            kSecAttrService as String: keychainService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status != errSecItemNotFound else { return [] }
        guard status == errSecSuccess, let data = item as? Data else {
            throw SecureEnclaveUserStoreError.failedLoadingIdentitiesList
        }

        guard let identitiesList = try? JSONDecoder().decode([String].self, from: data) else {
            throw SecureEnclaveUserStoreError.failedLoadingIdentitiesList
        }

        return identitiesList
    }

    private func saveIdentitiesList(_ identitiesList: [String]) throws {
        let data = try JSONEncoder().encode(identitiesList)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: identitiesListKey,
            kSecAttrService as String: keychainService,
            kSecValueData as String: data
        ]

        SecItemDelete(query as CFDictionary) // Delete first to avoid duplicates

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SecureEnclaveUserStoreError.failedSavingIdentitiesList
        }
    }

    private func addIdentityIdToList(_ identityId: String) throws {
        var identitiesList = try loadIdentitiesList()
        if !identitiesList.contains(identityId) {
            identitiesList.append(identityId)
            try saveIdentitiesList(identitiesList)
        }
    }

    private func removeIdentityIdFromList(_ identityId: String) throws {
        var identitiesList = try loadIdentitiesList()
        identitiesList.removeAll { $0 == identityId }
        try saveIdentitiesList(identitiesList)
    }

    private func deleteInboxId(for identityId: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "\(identityId.lowercased()).inboxId",
            kSecAttrService as String: keychainService
        ]
        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SecureEnclaveUserStoreError.failedDeletingInboxId
        }
    }

    func save(inboxId: String, for identityId: String) throws {
        let identifier = identityId.lowercased()

        guard let inboxIdData = inboxId.data(using: .utf8) else {
            throw SecureEnclaveUserStoreError.failedSavingInboxId
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "\(identifier).inboxId",
            kSecAttrService as String: keychainService,
            kSecValueData as String: inboxIdData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        SecItemDelete(query as CFDictionary) // Delete first to avoid duplicates

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SecureEnclaveUserStoreError.failedSavingInboxId
        }
    }

    func loadInboxId(for identityId: String) throws -> String {
        let identifier = identityId.lowercased()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "\(identifier).inboxId",
            kSecAttrService as String: keychainService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess, let data = item as? Data else {
            throw SecureEnclaveUserStoreError.failedLoadingInboxId
        }

        guard let inboxId = String(data: data, encoding: .utf8) else {
            throw SecureEnclaveUserStoreError.failedLoadingInboxId
        }

        return inboxId
    }

    func save(providerId: String, for inboxId: String) throws {
        guard let providerIdData = providerId.data(using: .utf8) else {
            throw SecureEnclaveUserStoreError.failedSavingProviderId
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "providerId.\(inboxId)",
            kSecAttrService as String: keychainService,
            kSecValueData as String: providerIdData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        SecItemDelete(query as CFDictionary) // Delete first to avoid duplicates

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SecureEnclaveUserStoreError.failedSavingProviderId
        }
    }

    func loadProviderId(for inboxId: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "providerId.\(inboxId)",
            kSecAttrService as String: keychainService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess, let data = item as? Data else {
            throw SecureEnclaveUserStoreError.failedLoadingProviderId
        }

        guard let providerId = String(data: data, encoding: .utf8) else {
            throw SecureEnclaveUserStoreError.failedLoadingProviderId
        }

        return providerId
    }

    private func saveInboxType(type: InboxType, for identityId: String) throws {
        let identifier = identityId.lowercased()
        let typeData = try JSONEncoder().encode(type)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "\(identifier).inboxType",
            kSecAttrService as String: keychainService,
            kSecValueData as String: typeData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        SecItemDelete(query as CFDictionary) // Delete first to avoid duplicates

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SecureEnclaveUserStoreError.failedSavingInboxType
        }
    }

    private func loadInboxType(for identityId: String) throws -> InboxType {
        let identifier = identityId.lowercased()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "\(identifier).inboxType",
            kSecAttrService as String: keychainService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess, let data = item as? Data else {
            throw SecureEnclaveUserStoreError.failedRetrievingInboxType
        }

        return try JSONDecoder().decode(InboxType.self, from: data)
    }
}
