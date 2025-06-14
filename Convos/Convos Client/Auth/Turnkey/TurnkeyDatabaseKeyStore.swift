import Foundation
import LocalAuthentication
import Security

class TurnkeyDatabaseKeyStore {
    static let shared: TurnkeyDatabaseKeyStore = .init()
    private let keychainService: String = "com.convos.ios.SecureEnclaveIdentityStore"

    enum TurnkeyDatabaseKeyStoreError: Error {
        case failedRetrievingDatabaseKey,
             failedDeletingDatabaseKey,
             failedSavingDatabaseKey,
             failedGeneratingDatabaseKey
    }

    private init() {}

    func databaseKey(for userId: String) throws -> Data {
        if let databaseKey = try loadDatabaseKey(for: userId) {
            return databaseKey
        } else {
            return try generateAndSaveDatabaseKey(for: userId)
        }
    }

    private func generateAndSaveDatabaseKey(for userId: String) throws -> Data {
        let databaseKey = Data((0..<32).map { _ in UInt8.random(in: UInt8.min...UInt8.max) })
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: userId,
            kSecAttrService as String: keychainService,
            kSecValueData as String: databaseKey,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw TurnkeyDatabaseKeyStoreError.failedSavingDatabaseKey
        }
        return databaseKey
    }

    private func loadDatabaseKey(for userId: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: userId,
            kSecAttrService as String: keychainService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status != errSecItemNotFound else { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw TurnkeyDatabaseKeyStoreError.failedRetrievingDatabaseKey
        }

        return data
    }
}
