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
    private let keyTagString: String = "com.convos.ios.SecureEnclaveIdentityStore.secp256k1"
    private let identitiesListKey: String = "com.convos.ios.SecureEnclaveIdentityStore.identitiesList"

    enum SecureEnclaveUserStoreError: Error {
        case failedRetrievingDatabaseKey,
             failedRetrievingInboxType,
             failedDeletingDatabaseKey,
             failedDeletingPrivateKey,
             failedSavingDatabaseKey,
             failedSavingInboxType,
             failedGeneratingDatabaseKey,
             keyTagMismatch,
             biometryAuthFailed,
             privateKeyNotFound,
             failedGeneratingPrivateKey,
             failedSavingIdentitiesList,
             failedLoadingIdentitiesList
    }

    func save(type: InboxType) throws -> SecureEnclaveIdentity {
        let identityId = UUID().uuidString
        let privateKey = try generatePrivateKeyWithBiometry(for: identityId)
        let databaseKey = try generateAndSaveDatabaseKey(for: identityId)

        try saveInboxType(type: type, for: identityId)
        try addIdentityIdToList(identityId)

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
        let privateKey = try loadPrivateKeyWithBiometry(for: identityId)
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
            if let identity = try load(for: identityId) {
                identities.append(identity)
            }
        }

        return identities
    }

    func delete(for identityId: String) throws {
        let databaseKeyQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: identityId,
            kSecAttrService as String: keychainService
        ]

        let databaseKeyStatus = SecItemDelete(databaseKeyQuery as CFDictionary)
        guard databaseKeyStatus == errSecSuccess || databaseKeyStatus == errSecItemNotFound else {
            throw SecureEnclaveUserStoreError.failedDeletingDatabaseKey
        }

        let keyTag = Data("\(keyTagString).\(identityId)".utf8)

        let privateKeyQuery: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: keyTag
        ]

        let privateKeyStatus = SecItemDelete(privateKeyQuery as CFDictionary)
        guard privateKeyStatus == errSecSuccess || privateKeyStatus == errSecItemNotFound else {
            throw SecureEnclaveUserStoreError.failedDeletingPrivateKey
        }

        try removeIdentityIdFromList(identityId)
    }

    // MARK: - Private Helpers

    private func generatePrivateKeyWithBiometry(for identityId: String) throws -> PrivateKey {
        let keyTag = Data("\(keyTagString).\(identityId)".utf8)

        let privateKey = try PrivateKey.generate()

        guard let accessControl = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleAfterFirstUnlock,
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

    private func loadPrivateKeyWithBiometry(for identityId: String) throws -> PrivateKey {
        let keyTag = Data("\(keyTagString).\(identityId)".utf8)

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

    private func loadIdentitiesList() throws -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: identitiesListKey,
            kSecAttrService as String: keychainService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
//            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
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
            kSecValueData as String: data,
//            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let attributesToUpdate: [String: Any] = [
                kSecValueData as String: data
            ]
            var updateQuery = query
            updateQuery.removeValue(forKey: kSecValueData as String)
            let updateStatus = SecItemUpdate(updateQuery as CFDictionary, attributesToUpdate as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw SecureEnclaveUserStoreError.failedSavingIdentitiesList
            }
        } else if status != errSecSuccess {
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

        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            Logger.info("Inbox type found for identifier: \(identifier), overwriting...")
            let attributesToUpdate: [String: Any] = [
                kSecValueData as String: typeData
            ]
            var updateQuery = query
            updateQuery.removeValue(forKey: kSecValueData as String)
            let updateStatus = SecItemUpdate(updateQuery as CFDictionary, attributesToUpdate as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw SecureEnclaveUserStoreError.failedSavingInboxType
            }
        } else if status != errSecSuccess {
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
