import Foundation
import Security

/// Secure storage for environment configuration using iOS Keychain
public extension AppEnvironment {
    /// Stores the current environment configuration securely in the Keychain
    func storeSecureConfigurationForNotificationExtension() {
        let sharedConfig = SharedAppConfiguration(environment: self)

        guard let data = try? JSONEncoder().encode(sharedConfig) else {
            Logger.error("Failed to encode environment configuration")
            return
        }

        // Store in Keychain with app group access
        let keychainQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "SharedAppConfiguration",
            kSecAttrService as String: "ConvosEnvironment",
            kSecAttrAccessGroup as String: appGroupIdentifier,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        // Delete any existing item first
        SecItemDelete(keychainQuery as CFDictionary)

        // Add the new item
        let status = SecItemAdd(keychainQuery as CFDictionary, nil)

        if status == errSecSuccess {
            Logger.info("Environment configuration stored securely in Keychain")
        } else {
            Logger.error("Failed to store environment configuration in Keychain: \(status)")
        }
    }

    /// Retrieves stored environment configuration securely from the Keychain
    /// - Parameter accessGroup: The keychain access group to use (required for proper data sharing)
    static func retrieveSecureConfigurationForNotificationExtension() -> AppEnvironment? {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier,
              let appGroupIdentifier = bundleIdentifier.asAppGroupIdentifier else {
            return nil
        }

        // Try to retrieve from Keychain
        let keychainQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "SharedAppConfiguration",
            kSecAttrService as String: "ConvosEnvironment",
            kSecAttrAccessGroup as String: appGroupIdentifier,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(keychainQuery as CFDictionary, &result)

        if status == errSecSuccess,
           let data = result as? Data,
           let sharedConfig = try? JSONDecoder().decode(SharedAppConfiguration.self, from: data) {
            Logger.info("Environment configuration retrieved from Keychain")
            return sharedConfig.toAppEnvironment()
        } else if status != errSecItemNotFound {
            Logger.error("Failed to retrieve environment configuration from Keychain: \(status)")
        }

        return nil
    }
}

extension String {
    var asAppGroupIdentifier: String? {
        var parts = self.split(separator: ".")
        guard parts.count > 1 else { return nil }
        parts.removeLast()
        return "group." + parts.joined(separator: ".")
    }
}
