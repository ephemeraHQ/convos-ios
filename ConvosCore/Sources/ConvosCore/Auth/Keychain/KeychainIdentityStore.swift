import CryptoKit
import Foundation
import LocalAuthentication
import Security
import XMTPiOS

// MARK: - Models

protocol XMTPClientKeys {
    var signingKey: any XMTPiOS.SigningKey { get }
    var databaseKey: Data { get }
}

public struct KeychainIdentityKeys: Codable, XMTPClientKeys {
    public let privateKey: PrivateKey
    public let databaseKey: Data

    public var signingKey: any SigningKey {
        privateKey
    }

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

protocol KeychainIdentityType {
    var inboxId: String { get }
    var clientKeys: any XMTPClientKeys { get }
}

public struct KeychainIdentity: Codable, KeychainIdentityType {
    public let inboxId: String
    public let clientId: String
    public let keys: KeychainIdentityKeys
    var clientKeys: any XMTPClientKeys {
        keys
    }

    init(inboxId: String, clientId: String, keys: KeychainIdentityKeys) {
        self.inboxId = inboxId
        self.clientId = clientId
        self.keys = keys
    }
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
    case duplicateClientId(String, Int)

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
        case let .identityNotFound(context):
            return "Identity not found: \(context)"
        case let .rollbackFailed(context):
            return "Rollback failed for \(context)"
        case .invalidAccessGroup:
            return "Invalid or missing keychain access group"
        case let .duplicateClientId(clientId, count):
            return "Duplicate clientId detected: '\(clientId)' found \(count) times in keychain"
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
    let clientId: String?

    init(
        account: String,
        service: String,
        accessGroup: String,
        accessible: CFString = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        accessControl: SecAccessControl? = nil,
        clientId: String? = nil
    ) {
        self.account = account
        self.service = service
        self.accessGroup = accessGroup
        self.accessible = accessible
        self.accessControl = accessControl
        self.clientId = clientId
    }

    func toDictionary() -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: service,
            kSecAttrAccessGroup as String: accessGroup
        ]

        // Add clientId as generic attribute for direct lookup
        if let clientId = clientId, let clientIdData = clientId.data(using: .utf8) {
            query[kSecAttrGeneric as String] = clientIdData
        }

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

public protocol KeychainIdentityStoreProtocol: Actor {
    func generateKeys() throws -> KeychainIdentityKeys
    func save(inboxId: String, clientId: String, keys: KeychainIdentityKeys) throws -> KeychainIdentity
    func identity(for inboxId: String) throws -> KeychainIdentity
    func loadAll() throws -> [KeychainIdentity]
    func delete(inboxId: String) throws
    func delete(clientId: String) throws
    func deleteAll() throws
}

public final actor KeychainIdentityStore: KeychainIdentityStoreProtocol {
    // MARK: - Properties

    private let keychainService: String
    private let keychainAccessGroup: String

    // MARK: - Initialization

    public init(accessGroup: String, service: String = "org.convos.ios.KeychainIdentityStore") {
        self.keychainAccessGroup = accessGroup
        self.keychainService = service
    }

    // MARK: - Public Interface

    public func generateKeys() throws -> KeychainIdentityKeys {
        try KeychainIdentityKeys.generate()
    }

    public func save(inboxId: String, clientId: String, keys: KeychainIdentityKeys) throws -> KeychainIdentity {
        let identity = KeychainIdentity(
            inboxId: inboxId,
            clientId: clientId,
            keys: keys
        )
        try save(identity: identity)
        return identity
    }

    public func identity(for inboxId: String) throws -> KeychainIdentity {
        let query = KeychainQuery(
            account: inboxId,
            service: keychainService,
            accessGroup: keychainAccessGroup
        )
        let data = try loadData(with: query)
        return try JSONDecoder().decode(KeychainIdentity.self, from: data)
    }

    // MARK: - Private lookup by clientId

    private func identity(forClientId clientId: String) throws -> KeychainIdentity {
        // Query keychain directly using clientId as generic attribute
        guard let clientIdData = clientId.data(using: .utf8) else {
            throw KeychainIdentityStoreError.identityNotFound("Invalid clientId encoding: \(clientId)")
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccessGroup as String: keychainAccessGroup,
            kSecAttrGeneric as String: clientIdData,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status != errSecItemNotFound else {
            throw KeychainIdentityStoreError.identityNotFound("No identity found with clientId: \(clientId)")
        }

        guard status == errSecSuccess else {
            throw KeychainIdentityStoreError.keychainOperationFailed(status, "identity(forClientId:)")
        }

        // Verify exactly one match exists
        let items: [Data]
        if let singleItem = result as? Data {
            // Single item returned
            items = [singleItem]
        } else if let multipleItems = result as? [Data] {
            // Multiple items returned
            items = multipleItems
        } else {
            throw KeychainIdentityStoreError.keychainOperationFailed(errSecUnknownFormat, "identity(forClientId:)")
        }

        guard items.count == 1 else {
            throw KeychainIdentityStoreError.duplicateClientId(clientId, items.count)
        }

        return try JSONDecoder().decode(KeychainIdentity.self, from: items[0])
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

    public func delete(inboxId: String) throws {
        let query = KeychainQuery(
            account: inboxId,
            service: keychainService,
            accessGroup: keychainAccessGroup
        )

        try deleteData(with: query)
    }

    public func delete(clientId: String) throws {
        // Direct lookup using clientId as a keychain attribute
        let identity = try identity(forClientId: clientId)

        // Delete using the inboxId (which is the account key in keychain)
        try delete(inboxId: identity.inboxId)
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

    // MARK: - Private Methods

    private func save(identity: KeychainIdentity) throws {
        // First, check if a different identity with the same clientId already exists
        // This enforces clientId uniqueness before saving
        do {
            let existingIdentity = try self.identity(forClientId: identity.clientId)

            // If we found an identity with this clientId, make sure it's the same inboxId
            // (updating the same identity is OK, but a different identity with same clientId is not)
            if existingIdentity.inboxId != identity.inboxId {
                throw KeychainIdentityStoreError.duplicateClientId(
                    identity.clientId,
                    2 // At least 2: the existing one and the one we're trying to save
                )
            }
            // If inboxId matches, we're updating the same identity, which is allowed
        } catch KeychainIdentityStoreError.identityNotFound {
            // No existing identity with this clientId - good, we can proceed
        }

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
            account: identity.inboxId,
            service: keychainService,
            accessGroup: keychainAccessGroup,
            accessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            accessControl: accessControl,
            clientId: identity.clientId
        )

        try saveData(data, with: query)
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
}
