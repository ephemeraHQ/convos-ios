import CryptoKit
import Foundation
import LocalAuthentication
import Security
import XMTPiOS

// MARK: - Models

struct KeychainIdentity {
    let id: String
    let privateKey: PrivateKey
    let databaseKey: Data
    let type: InboxType
}

// MARK: - Errors

enum KeychainIdentityStoreError: Error, LocalizedError {
    case keychainOperationFailed(OSStatus, String)
    case dataEncodingFailed(String)
    case dataDecodingFailed(String)
    case privateKeyGenerationFailed
    case privateKeyLoadingFailed
    case identityNotFound(String)
    case rollbackFailed(String)
    case invalidAccessGroup

    var errorDescription: String? {
        switch self {
        case let .keychainOperationFailed(status, operation):
            return "Keychain \(operation) failed with status: \(status)"
        case let .dataEncodingFailed(context):
            return "Failed to encode data for \(context)"
        case let .dataDecodingFailed(context):
            return "Failed to decode data for \(context)"
        case .privateKeyGenerationFailed:
            return "Failed to generate private key"
        case .privateKeyLoadingFailed:
            return "Failed to load private key"
        case let .identityNotFound(id):
            return "Identity not found: \(id)"
        case let .rollbackFailed(context):
            return "Rollback failed for \(context)"
        case .invalidAccessGroup:
            return "Invalid or missing keychain access group"
        }
    }
}

// MARK: - Keychain Operations

private struct KeychainQuery {
    let account: String
    let service: String
    let accessGroup: String
    let accessible: CFString
    let accessControl: SecAccessControl?

    init(
        account: String,
        service: String,
        accessGroup: String,
        accessible: CFString = kSecAttrAccessibleAfterFirstUnlock,
        accessControl: SecAccessControl? = nil
    ) {
        self.account = account
        self.service = service
        self.accessGroup = accessGroup
        self.accessible = accessible
        self.accessControl = accessControl
    }

    func toDictionary() -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: service,
            kSecAttrAccessGroup as String: accessGroup
        ]

        if let accessControl = accessControl {
            query[kSecAttrAccessControl as String] = accessControl
        } else {
            query[kSecAttrAccessible as String] = accessible
        }

        return query
    }

    func toReadDictionary() -> [String: Any] {
        var query = toDictionary()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return query
    }
}

// MARK: - Keychain Identity Store

protocol KeychainIdentityStoreProtocol {
    func save(type: InboxType) throws -> KeychainIdentity
    func load(for identityId: String) throws -> KeychainIdentity?
    func loadAll() throws -> [KeychainIdentity]
    func delete(for identityId: String) throws
    func save(inboxId: String, for identityId: String) throws
    func loadInboxId(for identityId: String) throws -> String
    func save(providerId: String, for inboxId: String) throws
    func loadProviderId(for inboxId: String) throws -> String
    func deleteProviderId(for inboxId: String) throws
}

final class KeychainIdentityStore: KeychainIdentityStoreProtocol {
    // MARK: - Properties

    private let keychainService: String
    private let keychainAccessGroup: String
    private let identitiesListKey: String

    // MARK: - Initialization

    init(accessGroup: String, service: String = "com.convos.ios.KeychainIdentityStore") {
        self.keychainAccessGroup = accessGroup
        self.keychainService = service
        self.identitiesListKey = "\(service).identitiesList"
    }

    // MARK: - Public Interface

    func save(type: InboxType) throws -> KeychainIdentity {
        let identityId = UUID().uuidString

        // Create identity with rollback support
        return try withRollback(identityId: identityId) {
            let privateKey = try generatePrivateKey()
            try savePrivateKey(privateKey, for: identityId)

            let databaseKey = try generateAndSaveDatabaseKey(for: identityId)
            try saveInboxType(type: type, for: identityId)
            try addIdentityIdToList(identityId)

            return KeychainIdentity(
                id: identityId,
                privateKey: privateKey,
                databaseKey: databaseKey,
                type: type
            )
        }
    }

    func load(for identityId: String) throws -> KeychainIdentity? {
        guard let databaseKey = try loadDatabaseKey(for: identityId) else {
            return nil
        }

        let inboxType = try loadInboxType(for: identityId)
        let privateKey = try loadPrivateKey(for: identityId)

        return KeychainIdentity(
            id: identityId,
            privateKey: privateKey,
            databaseKey: databaseKey,
            type: inboxType
        )
    }

    func loadAll() throws -> [KeychainIdentity] {
        let identityIds = try loadIdentitiesList()
        var identities: [KeychainIdentity] = []

        for identityId in identityIds {
            do {
                if let identity = try load(for: identityId) {
                    identities.append(identity)
                }
            } catch {
                Logger.error("Failed loading identity \(identityId): \(error)")
            }
        }

        return identities
    }

    func delete(for identityId: String) throws {
        // Clean up provider ID mapping if it exists
        if let inboxId = try? loadInboxId(for: identityId) {
            try? deleteProviderId(for: inboxId)
        }

        // Delete all identity-related data
        try deleteInboxId(for: identityId)
        try removeIdentityIdFromList(identityId)
        try deleteInboxType(for: identityId)
        try deleteDatabaseKey(for: identityId)
        try deletePrivateKey(for: identityId)
    }

    func save(inboxId: String, for identityId: String) throws {
        let data = try encodeString(inboxId, context: "inboxId")
        let query = KeychainQuery(
            account: "\(identityId.lowercased()).inboxId",
            service: keychainService,
            accessGroup: keychainAccessGroup
        )

        try saveData(data, with: query)
    }

    func loadInboxId(for identityId: String) throws -> String {
        let query = KeychainQuery(
            account: "\(identityId.lowercased()).inboxId",
            service: keychainService,
            accessGroup: keychainAccessGroup
        )

        let data = try loadData(with: query)
        return try decodeString(from: data, context: "inboxId")
    }

    func save(providerId: String, for inboxId: String) throws {
        let data = try encodeString(providerId, context: "providerId")
        let query = KeychainQuery(
            account: "providerId.\(inboxId)",
            service: keychainService,
            accessGroup: keychainAccessGroup
        )

        try saveData(data, with: query)
    }

    func loadProviderId(for inboxId: String) throws -> String {
        let query = KeychainQuery(
            account: "providerId.\(inboxId)",
            service: keychainService,
            accessGroup: keychainAccessGroup
        )

        let data = try loadData(with: query)
        return try decodeString(from: data, context: "providerId")
    }

    func deleteProviderId(for inboxId: String) throws {
        let query = KeychainQuery(
            account: "providerId.\(inboxId)",
            service: keychainService,
            accessGroup: keychainAccessGroup
        )

        try deleteData(with: query)
    }

    // MARK: - Private Methods

    private func withRollback<T>(identityId: String, operation: () throws -> T) throws -> T {
        do {
            return try operation()
        } catch {
            // Attempt rollback
            try? rollbackIdentity(identityId)
            throw error
        }
    }

    private func rollbackIdentity(_ identityId: String) throws {
        let operations = [
            { try? self.deletePrivateKey(for: identityId) },
            { try? self.deleteDatabaseKey(for: identityId) },
            { try? self.deleteInboxType(for: identityId) },
            { try? self.removeIdentityIdFromList(identityId) }
        ]

        for operation in operations {
            operation()
        }
    }

    // MARK: - Private Key Operations

    private func generatePrivateKey() throws -> PrivateKey {
        do {
            return try PrivateKey.generate()
        } catch {
            throw KeychainIdentityStoreError.privateKeyGenerationFailed
        }
    }

    private func savePrivateKey(_ privateKey: PrivateKey, for identityId: String) throws {
        let privateKeyData = privateKey.secp256K1.bytes

        guard let accessControl = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            [],
            nil
        ) else {
            throw KeychainIdentityStoreError.keychainOperationFailed(errSecNotAvailable, "create access control")
        }

        let query = KeychainQuery(
            account: "\(identityId).privateKey",
            service: keychainService,
            accessGroup: keychainAccessGroup,
            accessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            accessControl: accessControl
        )

        try saveData(privateKeyData, with: query)
    }

    private func loadPrivateKey(for identityId: String) throws -> PrivateKey {
        let context = LAContext()
        context.localizedReason = "Authenticate to access your Convos account"

        var query = KeychainQuery(
            account: "\(identityId).privateKey",
            service: keychainService,
            accessGroup: keychainAccessGroup
        ).toReadDictionary()

        query[kSecUseAuthenticationContext as String] = context

        let data = try loadData(with: query)
        return try PrivateKey(data)
    }

    private func deletePrivateKey(for identityId: String) throws {
        let query = KeychainQuery(
            account: "\(identityId).privateKey",
            service: keychainService,
            accessGroup: keychainAccessGroup
        )

        try deleteData(with: query)
    }

    // MARK: - Database Key Operations

    private func generateAndSaveDatabaseKey(for identityId: String) throws -> Data {
        let databaseKey = Data((0..<32).map { _ in UInt8.random(in: UInt8.min...UInt8.max) })
        try saveDatabaseKey(databaseKey, for: identityId)
        return databaseKey
    }

    private func saveDatabaseKey(_ databaseKey: Data, for identityId: String) throws {
        let query = KeychainQuery(
            account: identityId.lowercased(),
            service: keychainService,
            accessGroup: keychainAccessGroup
        )

        try saveData(databaseKey, with: query)
    }

    private func loadDatabaseKey(for identityId: String) throws -> Data? {
        let query = KeychainQuery(
            account: identityId.lowercased(),
            service: keychainService,
            accessGroup: keychainAccessGroup
        )

        return try? loadData(with: query)
    }

    private func deleteDatabaseKey(for identityId: String) throws {
        let query = KeychainQuery(
            account: identityId.lowercased(),
            service: keychainService,
            accessGroup: keychainAccessGroup
        )

        try deleteData(with: query)
    }

    // MARK: - Inbox Type Operations

    private func saveInboxType(type: InboxType, for identityId: String) throws {
        let data = try JSONEncoder().encode(type)
        let query = KeychainQuery(
            account: "\(identityId.lowercased()).inboxType",
            service: keychainService,
            accessGroup: keychainAccessGroup
        )

        try saveData(data, with: query)
    }

    private func loadInboxType(for identityId: String) throws -> InboxType {
        let query = KeychainQuery(
            account: "\(identityId.lowercased()).inboxType",
            service: keychainService,
            accessGroup: keychainAccessGroup
        )

        let data = try loadData(with: query)
        return try JSONDecoder().decode(InboxType.self, from: data)
    }

    private func deleteInboxType(for identityId: String) throws {
        let query = KeychainQuery(
            account: "\(identityId.lowercased()).inboxType",
            service: keychainService,
            accessGroup: keychainAccessGroup
        )

        try deleteData(with: query)
    }

    // MARK: - Inbox ID Operations

    private func deleteInboxId(for identityId: String) throws {
        let query = KeychainQuery(
            account: "\(identityId.lowercased()).inboxId",
            service: keychainService,
            accessGroup: keychainAccessGroup
        )

        try deleteData(with: query)
    }

    // MARK: - Identities List Operations

    private func loadIdentitiesList() throws -> [String] {
        let query = KeychainQuery(
            account: identitiesListKey,
            service: keychainService,
            accessGroup: keychainAccessGroup
        )

        guard let data = try? loadData(with: query) else {
            return []
        }

        return try JSONDecoder().decode([String].self, from: data)
    }

    private func saveIdentitiesList(_ identitiesList: [String]) throws {
        let data = try JSONEncoder().encode(identitiesList)
        let query = KeychainQuery(
            account: identitiesListKey,
            service: keychainService,
            accessGroup: keychainAccessGroup
        )

        try saveData(data, with: query)
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

    // MARK: - Generic Keychain Operations

    private func saveData(_ data: Data, with query: KeychainQuery) throws {
        var queryDict = query.toDictionary()
        queryDict[kSecValueData as String] = data

        let status = SecItemAdd(queryDict as CFDictionary, nil)

        if status == errSecDuplicateItem {
            // Item exists, update it
            let updateQuery = query.toDictionary()
            let attributesToUpdate: [String: Any] = [kSecValueData as String: data]

            let updateStatus = SecItemUpdate(updateQuery as CFDictionary, attributesToUpdate as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw KeychainIdentityStoreError.keychainOperationFailed(updateStatus, "update")
            }
        } else if status != errSecSuccess {
            throw KeychainIdentityStoreError.keychainOperationFailed(status, "add")
        }
    }

    private func loadData(with query: KeychainQuery) throws -> Data {
        return try loadData(with: query.toReadDictionary())
    }

    private func loadData(with query: [String: Any]) throws -> Data {
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status != errSecItemNotFound else {
            throw KeychainIdentityStoreError.identityNotFound("Data not found in keychain")
        }

        guard status == errSecSuccess, let data = item as? Data else {
            throw KeychainIdentityStoreError.keychainOperationFailed(status, "load")
        }

        return data
    }

    private func deleteData(with query: KeychainQuery) throws {
        let status = SecItemDelete(query.toDictionary() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainIdentityStoreError.keychainOperationFailed(status, "delete")
        }
    }

    // MARK: - Data Encoding/Decoding

    private func encodeString(_ string: String, context: String) throws -> Data {
        guard let data = string.data(using: .utf8) else {
            throw KeychainIdentityStoreError.dataEncodingFailed(context)
        }
        return data
    }

    private func decodeString(from data: Data, context: String) throws -> String {
        guard let string = String(data: data, encoding: .utf8) else {
            throw KeychainIdentityStoreError.dataDecodingFailed(context)
        }
        return string
    }
}

// MARK: - Debug Support

extension KeychainIdentityStore {
    /// WARNING: This will delete ALL keychain data for this service. Use only for debugging/development.
    func debugWipeAllKeychainData() {
        Logger.warning("🚨 WIPING ALL KEYCHAIN DATA FOR SERVICE: \(keychainService)")
        Logger.info("Configured keychain access group: \(keychainAccessGroup)")

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccessGroup as String: keychainAccessGroup
        ]

        let status = SecItemDelete(query as CFDictionary)
        switch status {
        case errSecSuccess:
            Logger.info("✅ Successfully deleted keychain items")
        case errSecItemNotFound:
            Logger.info("ℹ️ No keychain items found to delete")
        default:
            Logger.warning("⚠️ Failed to delete keychain items: \(status)")
        }

        Logger.warning("🚨 KEYCHAIN WIPE COMPLETE")
    }
}
