import AuthenticationServices
import Combine
import Foundation
import PasskeyAuth
import Security

public final class PasskeyAuthHelper {
    public enum PasskeyAuthError: Error, LocalizedError {
        case registrationFailed
        case missingCredentialID
        case loginFailed
        case storeKeyFailed
        case keyGenerationFailed
        case keyDeletionFailed
        case keychainError(OSStatus)
        case sessionStorageFailed
        case sessionDeletionFailed

        public var errorDescription: String? {
            switch self {
            case .registrationFailed: return "Registration failed"
            case .missingCredentialID: return "Missing credential ID"
            case .loginFailed: return "Login failed"
            case .storeKeyFailed: return "Failed to store XMTP key"
            case .keyGenerationFailed: return "Failed generating XMTP key"
            case .keyDeletionFailed: return "Failed deleting XMTP key"
            case .keychainError(let status): return "Keychain error (OSStatus: \(status))"
            case .sessionStorageFailed: return "Failed to store credentialID"
            case .sessionDeletionFailed: return "Failed deleting session"
            }
        }
    }

    private let passkeyAuth: PasskeyAuth
    private let service: String = "com.convos.ios.PasskeyAuthHelper"

    public init(baseURL: URL, rpID: String) throws {
        let endpoints = PasskeyEndpoints()
        let config = try PasskeyConfiguration(
            baseURL: baseURL,
            rpID: rpID,
            endpoints: endpoints
        )
        self.passkeyAuth = PasskeyAuth(configuration: config)
    }

    func setupPasskeyPresentationProvider() async {
        let presentationProvider = await PasskeyPresentationProvider()
        await passkeyAuth.setPresentationContextProvider(presentationProvider)
    }

    public func registerPasskey(displayName: String) async throws -> Data {
        let response = try await passkeyAuth.registerPasskey(displayName: displayName)
        guard response.success else {
            throw PasskeyAuthError.registrationFailed
        }
        guard let credID = try extractCredentialID(fromJWT: response.token) else {
            throw PasskeyAuthError.missingCredentialID
        }
        try SessionManager.setActiveCredentialID(credID)
        let privateKey = try generateNewXMTPPrivateKey()
        try storeXMTPPrivateKey(privateKey, for: credID)
        return privateKey
    }

    public func loginWithPasskey() async throws -> Data {
        let response = try await passkeyAuth.loginWithPasskey()
        guard response.success else {
            throw PasskeyAuthError.loginFailed
        }
        guard let credID = try extractCredentialID(fromJWT: response.token) else {
            throw PasskeyAuthError.missingCredentialID
        }
        try SessionManager.setActiveCredentialID(credID)
        let privateKey: Data
        if let key = try loadXMTPPrivateKey(for: credID) {
            privateKey = key
        } else {
            let key = try generateNewXMTPPrivateKey()
            try storeXMTPPrivateKey(key, for: credID)
            privateKey = key
        }
        return privateKey
    }

    public func logout() {
        do {
            try deletePrivateKey()
            try SessionManager.clearActiveCredentialID()
        } catch {
            Logger.error("Failed signing out: \(error)")
        }
    }

    public func activePrivateKey() throws -> Data? {
        guard let credID = SessionManager.getActiveCredentialID() else {
            return nil
        }
        return try loadXMTPPrivateKey(for: credID)
    }

    private func generateNewXMTPPrivateKey() throws -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw PasskeyAuthError.keyGenerationFailed
        }
        return Data(bytes)
    }

    private func deletePrivateKey() throws {
        if let credID = SessionManager.getActiveCredentialID() {
            let query: [CFString: Any] = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: service,
                kSecAttrAccount: credID
            ]
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess else {
                throw PasskeyAuthError.keyDeletionFailed
            }
        }
    }

    private func storeXMTPPrivateKey(_ keyData: Data, for credentialID: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: credentialID,
            kSecValueData: keyData,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw PasskeyAuthError.storeKeyFailed
        }
    }

    private func loadXMTPPrivateKey(for credentialID: String) throws -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: credentialID,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess {
            return item as? Data
        } else if status == errSecItemNotFound {
            return nil
        } else {
            throw PasskeyAuthError.keychainError(status)
        }
    }

    private func extractCredentialID(fromJWT token: String) throws -> String? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var base64 = String(parts[1])
        let remainder = base64.count % 4
        if remainder > 0 { base64 += String(repeating: "=", count: 4 - remainder) }
        base64 = base64.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        guard let payloadData = Data(base64Encoded: base64),
              let json = try JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
              let credID = json["credentialID"] as? String else {
            return nil
        }
        return credID
    }

    private struct SessionManager {
        private static let service: String = "com.convos.ios.PasskeySession"
        private static let key: String = "activeCredentialID"

        static func setActiveCredentialID(_ id: String) throws {
            let data = Data(id.utf8)
            let query: [CFString: Any] = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: service,
                kSecAttrAccount: key,
                kSecValueData: data,
                kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            ]
            SecItemDelete(query as CFDictionary)
            let status = SecItemAdd(query as CFDictionary, nil)
            guard status == errSecSuccess else {
                throw PasskeyAuthError.sessionStorageFailed
            }
        }

        static func getActiveCredentialID() -> String? {
            let query: [CFString: Any] = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: service,
                kSecAttrAccount: key,
                kSecReturnData: true,
                kSecMatchLimit: kSecMatchLimitOne
            ]
            var item: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &item)
            guard status == errSecSuccess, let data = item as? Data else {
                return nil
            }
            return String(data: data, encoding: .utf8)
        }

        static func clearActiveCredentialID() throws {
            let query: [CFString: Any] = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: service,
                kSecAttrAccount: key
            ]
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess else {
                throw PasskeyAuthError.sessionDeletionFailed
            }
        }
    }
}
