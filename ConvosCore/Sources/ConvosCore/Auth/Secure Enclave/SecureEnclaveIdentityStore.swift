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
    var keychainAccessGroup: String? { get }
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
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: identifier,
            kSecAttrService as String: keychainService,
            kSecValueData as String: databaseKey,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        if let accessGroup = keychainAccessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        } else {
            Logger.warning("⚠️ No keychain access group configured for database key storage")
        }
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
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: identifier,
            kSecAttrService as String: keychainService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        if let accessGroup = keychainAccessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        } else {
            Logger.warning("⚠️ No keychain access group configured for database key loading")
        }

        var item: CFTypeRef?
        var status = SecItemCopyMatching(query as CFDictionary, &item)

        // If not found with access group, try without access group for backward compatibility
        if status == errSecItemNotFound && keychainAccessGroup != nil {
            var fallbackQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: identifier,
                kSecAttrService as String: keychainService,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
            ]
            // Don't add access group for fallback
            status = SecItemCopyMatching(fallbackQuery as CFDictionary, &item)
        }

        guard status != errSecItemNotFound else { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw SecureEnclaveKeyStoreError.failedRetrievingDatabaseKey
        }

        return data
    }
}

final class SecureEnclaveIdentityStore: SecureEnclaveKeyStore {
    internal let keychainService: String = "com.convos.ios.SecureEnclaveIdentityStore"
    internal let keychainAccessGroup: String?

    init(accessGroup: String? = nil) {
        self.keychainAccessGroup = accessGroup
    }

    private let identitiesListKey: String = "com.convos.ios.SecureEnclaveIdentityStore.identitiesList"

    /// Adds keychain access group to a query. Access groups are required for proper data sharing.
    private func addAccessGroup(to query: inout [String: Any]) {
        guard let accessGroup = keychainAccessGroup else {
            Logger.warning("⚠️ No keychain access group configured - this may cause data sharing issues between app and extensions")
            return
        }
        query[kSecAttrAccessGroup as String] = accessGroup
    }

    enum SecureEnclaveUserStoreError: Error {
        case failedRetrievingDatabaseKey,
             failedRetrievingInboxType,
             failedDeletingDatabaseKey,
             failedDeletingPrivateKey,
             failedDeletingInboxType,
             failedDeletingInboxId,
             failedDeletingProviderId,
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
        // Attempt to delete provider ID mapping, but don't fail entire cleanup if this fails
        if let inboxId = try? loadInboxId(for: identityId) {
            do {
                try deleteProviderId(for: inboxId)
            } catch {
                Logger.error("Failed to delete provider ID for inbox \(inboxId): \(error). Continuing with cleanup...")
            }
        }
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
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "\(identityId).privateKey",
            kSecAttrService as String: keychainService
        ]
        addAccessGroup(to: &query)
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess else {
            throw SecureEnclaveUserStoreError.failedDeletingPrivateKey
        }
    }

    private func deleteDatabaseKey(for identityId: String) throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: identityId.lowercased(),
            kSecAttrService as String: keychainService
        ]
        addAccessGroup(to: &query)
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess else {
            throw SecureEnclaveUserStoreError.failedDeletingDatabaseKey
        }
    }

    private func deleteInboxType(for identityId: String) throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "\(identityId.lowercased()).inboxType",
            kSecAttrService as String: keychainService
        ]
        addAccessGroup(to: &query)
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess else {
            throw SecureEnclaveUserStoreError.failedDeletingInboxType
        }
    }

        private func loadIdentitiesList() throws -> [String] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: identitiesListKey,
            kSecAttrService as String: keychainService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        addAccessGroup(to: &query)

        var item: CFTypeRef?
        var status = SecItemCopyMatching(query as CFDictionary, &item)

        // If not found with access group, try without access group for backward compatibility
        if status == errSecItemNotFound && keychainAccessGroup != nil {
            var fallbackQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: identitiesListKey,
                kSecAttrService as String: keychainService,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]
            // Don't add access group for fallback
            status = SecItemCopyMatching(fallbackQuery as CFDictionary, &item)
        }

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

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: identitiesListKey,
            kSecAttrService as String: keychainService,
            kSecValueData as String: data
        ]

        addAccessGroup(to: &query)

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
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "\(identityId.lowercased()).inboxId",
            kSecAttrService as String: keychainService
        ]
        addAccessGroup(to: &query)
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess else {
            throw SecureEnclaveUserStoreError.failedDeletingInboxId
        }
    }

    func save(inboxId: String, for identityId: String) throws {
        let identifier = identityId.lowercased()

        guard let inboxIdData = inboxId.data(using: .utf8) else {
            throw SecureEnclaveUserStoreError.failedSavingInboxId
        }

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "\(identifier).inboxId",
            kSecAttrService as String: keychainService,
            kSecValueData as String: inboxIdData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        addAccessGroup(to: &query)

        SecItemDelete(query as CFDictionary) // Delete first to avoid duplicates

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SecureEnclaveUserStoreError.failedSavingInboxId
        }
    }

        func loadInboxId(for identityId: String) throws -> String {
        let identifier = identityId.lowercased()
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "\(identifier).inboxId",
            kSecAttrService as String: keychainService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        addAccessGroup(to: &query)

        var item: CFTypeRef?
        var status = SecItemCopyMatching(query as CFDictionary, &item)

        // If not found with access group, try without access group for backward compatibility
        if status == errSecItemNotFound && keychainAccessGroup != nil {
            var fallbackQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: "\(identifier).inboxId",
                kSecAttrService as String: keychainService,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
            ]
            // Don't add access group for fallback
            status = SecItemCopyMatching(fallbackQuery as CFDictionary, &item)
        }

        guard status == errSecSuccess, let data = item as? Data else {
            throw SecureEnclaveUserStoreError.failedLoadingInboxId
        }

        guard let inboxId = String(data: data, encoding: .utf8) else {
            throw SecureEnclaveUserStoreError.failedLoadingInboxId
        }

        return inboxId
    }

    func deleteProviderId(for inboxId: String) throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "providerId.\(inboxId)",
            kSecAttrService as String: keychainService,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        addAccessGroup(to: &query)

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess else {
            throw SecureEnclaveUserStoreError.failedDeletingProviderId
        }
    }

        func save(providerId: String, for inboxId: String) throws {
        Logger.info("💾 Saving provider ID mapping: \(inboxId) → \(providerId)")
        if let accessGroup = keychainAccessGroup {
            Logger.info("Using keychain access group: \(accessGroup)")
        } else {
            Logger.info("No keychain access group configured")
        }

        guard let providerIdData = providerId.data(using: .utf8) else {
            Logger.error("Failed to encode provider ID data")
            throw SecureEnclaveUserStoreError.failedSavingProviderId
        }

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "providerId.\(inboxId)",
            kSecAttrService as String: keychainService,
            kSecValueData as String: providerIdData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        addAccessGroup(to: &query)

        SecItemDelete(query as CFDictionary) // Delete first to avoid duplicates

        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecSuccess {
            Logger.info("✅ Successfully saved provider ID mapping")
        } else {
            Logger.error("❌ Failed to save provider ID mapping. Status: \(status)")
            throw SecureEnclaveUserStoreError.failedSavingProviderId
        }
    }

    func loadProviderId(for inboxId: String) throws -> String {
        Logger.info("Loading provider ID for inbox: \(inboxId)")
        if let accessGroup = keychainAccessGroup {
            Logger.info("Using keychain access group: \(accessGroup)")
        } else {
            Logger.info("No keychain access group configured")
        }

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "providerId.\(inboxId)",
            kSecAttrService as String: keychainService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        addAccessGroup(to: &query)

        var item: CFTypeRef?
        var status = SecItemCopyMatching(query as CFDictionary, &item)

        Logger.info("First query status: \(status)")

        // If not found with access group, try without access group for backward compatibility
        if status == errSecItemNotFound && keychainAccessGroup != nil {
            Logger.info("Trying fallback query without access group")
            var fallbackQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: "providerId.\(inboxId)",
                kSecAttrService as String: keychainService,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ]
            // Don't add access group for fallback
            status = SecItemCopyMatching(fallbackQuery as CFDictionary, &item)
            Logger.info("Fallback query status: \(status)")
        }

        guard status == errSecSuccess, let data = item as? Data else {
            Logger.error("Failed to load provider ID. Status: \(status)")
            throw SecureEnclaveUserStoreError.failedLoadingProviderId
        }

        guard let providerId = String(data: data, encoding: .utf8) else {
            Logger.error("Failed to decode provider ID data")
            throw SecureEnclaveUserStoreError.failedLoadingProviderId
        }

        Logger.info("Successfully loaded provider ID: \(providerId)")
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

    // MARK: - Debug/Development Methods

        /// Debug method to list all provider ID mappings in the keychain
    func debugListAllProviderIdMappings() {
        Logger.info("🔍 LISTING ALL PROVIDER ID MAPPINGS")

        // Query for all items with the providerId prefix
        let accessGroupsToTry = [keychainAccessGroup, nil]

        for accessGroup in accessGroupsToTry {
            var query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: keychainService,
                kSecReturnAttributes as String: true,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitAll
            ]

            if let accessGroup = accessGroup {
                query[kSecAttrAccessGroup as String] = accessGroup
                Logger.info("Searching with access group: \(accessGroup)")
            } else {
                Logger.info("Searching without access group")
            }

            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)

            if status == errSecSuccess, let items = result as? [[String: Any]] {
                Logger.info("Found \(items.count) keychain items")
                for item in items {
                    if let account = item[kSecAttrAccount as String] as? String,
                       account.hasPrefix("providerId."),
                       let data = item[kSecValueData as String] as? Data,
                       let providerId = String(data: data, encoding: .utf8) {
                        let inboxId = String(account.dropFirst("providerId.".count))
                        Logger.info("  \(inboxId) → \(providerId)")
                    } else if let account = item[kSecAttrAccount as String] as? String {
                        Logger.info("  Non-providerId item: \(account)")
                    }
                }
            } else {
                Logger.info("Query failed with status: \(status)")
            }
        }

        Logger.info("🔍 END PROVIDER ID MAPPINGS LIST")
    }

    /// WARNING: This will delete ALL keychain data for this service. Use only for debugging/development.
    /// Call this method temporarily to clear keychain data when testing keychain access group changes.
    func debugWipeAllKeychainData() {
        Logger.warning("🚨 WIPING ALL KEYCHAIN DATA FOR SERVICE: \(keychainService)")
        if let accessGroup = keychainAccessGroup {
            Logger.info("Configured keychain access group: \(accessGroup)")
        } else {
            Logger.info("No keychain access group configured")
        }

        // Delete all items for this service (with and without access groups)
        let servicesToClear = [keychainService]
        let accessGroupsToClear = [keychainAccessGroup, nil] // Try both with and without access group

        for service in servicesToClear {
            for accessGroup in accessGroupsToClear {
                var query: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: service
                ]

                if let accessGroup = accessGroup {
                    query[kSecAttrAccessGroup as String] = accessGroup
                    Logger.info("Deleting keychain items for service: \(service) with access group: \(accessGroup)")
                } else {
                    Logger.info("Deleting keychain items for service: \(service) without access group")
                }

                let status = SecItemDelete(query as CFDictionary)
                switch status {
                case errSecSuccess:
                    Logger.info("✅ Successfully deleted keychain items")
                case errSecItemNotFound:
                    Logger.info("ℹ️ No keychain items found to delete")
                default:
                    Logger.warning("⚠️ Failed to delete keychain items: \(status)")
                }
            }
        }

        Logger.warning("🚨 KEYCHAIN WIPE COMPLETE")
    }
}
