import Foundation
import Security

enum KeychainError: Error {
    case duplicateEntry
    case unknown(OSStatus)
    case itemNotFound
}

protocol KeychainItemProtocol {
    static var service: String { get }
    var account: String { get }
}

/// Generic keychain service for storing and retrieving items
///
/// Provides type-safe keychain operations for storing string and data values.
/// Items are identified by service and account identifiers, with automatic
/// updates for duplicate entries. Used internally by higher-level stores.
final class KeychainService<T: KeychainItemProtocol> {
    func saveString(_ value: String, for item: T) throws {
        guard let valueData = value.data(using: .utf8) else {
            throw KeychainError.unknown(errSecParam)
        }
        try saveData(valueData, for: item)
    }

    func saveData(_ data: Data, for item: T) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: T.service,
            kSecAttrAccount as String: item.account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        if status == errSecDuplicateItem {
            // Item already exists, update it
            let updateQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: T.service,
                kSecAttrAccount as String: item.account
            ]

            let attributes: [String: Any] = [
                kSecValueData as String: data
            ]

            let updateStatus = SecItemUpdate(updateQuery as CFDictionary, attributes as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw KeychainError.unknown(updateStatus)
            }
        } else if status != errSecSuccess {
            throw KeychainError.unknown(status)
        }
    }

    func retrieveString(_ item: T) throws -> String? {
        let result = try retrieveData(item)
        guard let data = result,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }

        return value
    }

    func retrieveData(_ item: T) throws -> Data? {
        return try retrieve(service: T.service, account: item.account)
    }

    private func retrieve(service: String, account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                return nil
            }
            throw KeychainError.unknown(status)
        }

        return result as? Data
    }

    private func delete(service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unknown(status)
        }
    }

    func delete(_ item: T) throws {
        try delete(service: T.service, account: item.account)
    }
}
