import Foundation

/// Mock keychain service for testing
///
/// Provides an in-memory implementation of KeychainServiceProtocol for unit tests.
/// All data is stored in memory and cleared when the instance is deallocated.
final class MockKeychainService: KeychainServiceProtocol, @unchecked Sendable {
    private var storage: [String: Data] = [:]
    private let queue: DispatchQueue = DispatchQueue(label: "com.convos.mockKeychainService", qos: .userInitiated)

    func saveString(_ value: String, account: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.unknown(errSecParam)
        }
        try saveData(data, account: account)
    }

    func saveData(_ data: Data, account: String) throws {
        queue.sync {
            storage[account] = data
        }
    }

    func retrieveString(account: String) throws -> String? {
        guard let data = try retrieveData(account: account) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func retrieveData(account: String) throws -> Data? {
        return queue.sync {
            storage[account]
        }
    }

    func delete(account: String) throws {
        queue.sync {
            _ = storage.removeValue(forKey: account)
        }
    }

    // Test helpers

    func clear() {
        queue.sync {
            storage.removeAll()
        }
    }

    func contains(account: String) -> Bool {
        return queue.sync {
            storage[account] != nil
        }
    }
}
