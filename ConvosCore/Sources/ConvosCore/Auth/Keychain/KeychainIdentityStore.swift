import CryptoKit
import Foundation
import LocalAuthentication
import Security
import XMTPiOS

// MARK: - Models

public struct KeychainIdentityKeys: Codable {
    public let privateKey: PrivateKey
    public let databaseKey: Data

    private enum CodingKeys: String, CodingKey {
        case privateKeyData
        case databaseKey
    }

    static func generate() throws -> KeychainIdentityKeys {
        let privateKey = try generatePrivateKey()
        let databaseKey = try generateDatabaseKey()
        return .init(privateKey: privateKey, databaseKey: databaseKey)
    }

    init(privateKey: PrivateKey, databaseKey: Data) {
        self.privateKey = privateKey
        self.databaseKey = databaseKey
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        databaseKey = try container.decode(Data.self, forKey: .databaseKey)
        let privateKeyData = try container.decode(Data.self, forKey: .privateKeyData)
        privateKey = try PrivateKey(privateKeyData)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(databaseKey, forKey: .databaseKey)
        try container.encode(privateKey.secp256K1.bytes, forKey: .privateKeyData)
    }

    private static func generatePrivateKey() throws -> PrivateKey {
        do {
            return try PrivateKey.generate()
        } catch {
            throw KeychainIdentityStoreError.privateKeyGenerationFailed
        }
    }

    private static func generateDatabaseKey() throws -> Data {
        var key = Data(count: 32) // 256-bit key
        let status: OSStatus = try key.withUnsafeMutableBytes { bytes in
            guard let baseAddress = bytes.baseAddress else {
                throw KeychainIdentityStoreError.keychainOperationFailed(errSecUnknownFormat, "generateDatabaseKey")
            }
            return SecRandomCopyBytes(kSecRandomDefault, 32, baseAddress)
        }

        guard status == errSecSuccess else {
            throw KeychainIdentityStoreError.keychainOperationFailed(status, "generateDatabaseKey")
        }

        return key
    }
}

public struct KeychainIdentity: Codable {
    public let id: String
    public let keys: KeychainIdentityKeys
}

// MARK: - Errors

public enum KeychainIdentityStoreError: Error, LocalizedError {
    case keychainOperationFailed(OSStatus, String)
    case dataEncodingFailed(String)
    case dataDecodingFailed(String)
    case privateKeyGenerationFailed
    case privateKeyLoadingFailed
    case identityNotFound(String)
    case rollbackFailed(String)
    case invalidAccessGroup

    public var errorDescription: String? {
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
        accessible: CFString = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
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

public protocol KeychainIdentityStoreProtocol {
    func save() throws -> KeychainIdentity
    func load(for identityId: String) throws -> KeychainIdentity?
    func loadAll() throws -> [KeychainIdentity]
    func delete(for identityId: String) throws
    func deleteAll() throws
    func save(inboxId: String, for identityId: String) throws
    func loadInboxId(for identityId: String) throws -> String
    func save(providerId: String, for inboxId: String) throws
    func loadProviderId(for inboxId: String) throws -> String
    func deleteProviderId(for inboxId: String) throws
}

public final class KeychainIdentityStore: KeychainIdentityStoreProtocol {
    // MARK: - Properties

    private let keychainService: String
    private let keychainAccessGroup: String

    // MARK: - Initialization

    public init(accessGroup: String, service: String = "org.convos.ios.KeychainIdentityStore") {
        self.keychainAccessGroup = accessGroup
        self.keychainService = service
    }

    // MARK: - Public Interface

    public func save() throws -> KeychainIdentity {
        let identityId = UUID().uuidString
        let keys = try KeychainIdentityKeys.generate()

        let identity = KeychainIdentity(
            id: identityId,
            keys: keys
        )

        try saveIdentity(identity)
        return identity
    }

    public func load(for identityId: String) throws -> KeychainIdentity? {
        let query = KeychainQuery(
            account: identityId,
            service: keychainService,
            accessGroup: keychainAccessGroup
        )

        do {
            let data = try loadData(with: query)
            return try JSONDecoder().decode(KeychainIdentity.self, from: data)
        } catch KeychainIdentityStoreError.identityNotFound {
            return nil
        }
    }

    public func loadAll() throws -> [KeychainIdentity] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccessGroup as String: keychainAccessGroup,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnData as String: true
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let items = result as? [Data] else {
            if status == errSecItemNotFound {
                return []
            }
            throw KeychainIdentityStoreError.keychainOperationFailed(status, "loadAll")
        }

        var identities: [KeychainIdentity] = []
        for data in items {
            do {
                let identity = try JSONDecoder().decode(KeychainIdentity.self, from: data)
                identities.append(identity)
            } catch {
                Logger.error("Failed decoding identity: \(error)")
            }
        }

        return identities
    }

    public func delete(for identityId: String) throws {
        // Clean up provider ID mapping if it exists
        if let inboxId = try? loadInboxId(for: identityId) {
            try? deleteProviderId(for: inboxId)
        }

        // Delete the identity
        let query = KeychainQuery(
            account: identityId,
            service: keychainService,
            accessGroup: keychainAccessGroup
        )

        try deleteData(with: query)

        // Delete inbox ID mapping
        try deleteInboxId(for: identityId)
    }

    public func deleteAll() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccessGroup as String: keychainAccessGroup
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainIdentityStoreError.keychainOperationFailed(status, "deleteAll")
        }
    }

    public func save(inboxId: String, for identityId: String) throws {
        let data = try encodeString(inboxId, context: "inboxId")
        let query = KeychainQuery(
            account: "\(identityId.lowercased()).inboxId",
            service: keychainService,
            accessGroup: keychainAccessGroup
        )

        try saveData(data, with: query)
    }

    public func loadInboxId(for identityId: String) throws -> String {
        let query = KeychainQuery(
            account: "\(identityId.lowercased()).inboxId",
            service: keychainService,
            accessGroup: keychainAccessGroup
        )

        let data = try loadData(with: query)
        return try decodeString(from: data, context: "inboxId")
    }

    public func save(providerId: String, for inboxId: String) throws {
        let data = try encodeString(providerId, context: "providerId")
        let query = KeychainQuery(
            account: "providerId.\(inboxId)",
            service: keychainService,
            accessGroup: keychainAccessGroup
        )

        try saveData(data, with: query)
    }

    public func loadProviderId(for inboxId: String) throws -> String {
        let query = KeychainQuery(
            account: "providerId.\(inboxId)",
            service: keychainService,
            accessGroup: keychainAccessGroup
        )

        let data = try loadData(with: query)
        return try decodeString(from: data, context: "providerId")
    }

    public func deleteProviderId(for inboxId: String) throws {
        let query = KeychainQuery(
            account: "providerId.\(inboxId)",
            service: keychainService,
            accessGroup: keychainAccessGroup
        )

        try deleteData(with: query)
    }

    // MARK: - Private Methods

    private func saveIdentity(_ identity: KeychainIdentity) throws {
        let data = try JSONEncoder().encode(identity)

        // Create access control for enhanced security
        guard let accessControl = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            [],
            nil
        ) else {
            throw KeychainIdentityStoreError.keychainOperationFailed(errSecNotAvailable, "create access control")
        }

        let query = KeychainQuery(
            account: identity.id,
            service: keychainService,
            accessGroup: keychainAccessGroup,
            accessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            accessControl: accessControl
        )

        try saveData(data, with: query)
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
