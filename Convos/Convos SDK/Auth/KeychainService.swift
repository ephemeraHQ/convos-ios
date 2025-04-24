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

final class KeychainService<T: KeychainItemProtocol> {
    func save(_ value: String, for item: T) throws {
        guard let valueString = value.data(using: .utf8) else {
            throw KeychainError.unknown(errSecParam)
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: T.service,
            kSecAttrAccount as String: item.account,
            kSecValueData as String: valueString
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
                kSecValueData as String: valueString
            ]

            let updateStatus = SecItemUpdate(updateQuery as CFDictionary, attributes as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw KeychainError.unknown(updateStatus)
            }
        } else if status != errSecSuccess {
            throw KeychainError.unknown(status)
        }
    }

    func retrieve(_ item: T) throws -> String? {
        return try retrieve(service: T.service, account: item.account)
    }

    private func retrieve(service: String, account: String) throws -> String? {
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

        guard let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }

        return value
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
