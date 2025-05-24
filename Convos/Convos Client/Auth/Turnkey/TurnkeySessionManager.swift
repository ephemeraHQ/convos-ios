import CryptoKit
import Foundation
import Shared
import TurnkeySDK

// swiftlint:disable force_cast force_unwrapping

class TurnkeySessionManager {
    public enum TurnkeySessionManagerError: Error {
        case keyGenerationFailed(Error)
        case keyRetrievalFailed(OSStatus)
        case publicKeyExtractionFailed
        case externalRepresentationFailed
        case keyNotFound
        case signingNotSupported
    }

    static var shared: TurnkeySessionManager = TurnkeySessionManager()
    private let sessionKey: String = "com.convos.ios.session"

    private init() {}

    func turnkeyClientFromActiveSession() throws -> TurnkeyClient? {
        guard let session = try loadActiveSession() else {
            return nil
        }
        let (publicKeyData, privateKeyData) = try publicPrivateKeyPair(for: session.keyTag)
        let publicKey = try P256.KeyAgreement.PublicKey(x963Representation: publicKeyData)
        let privateKey = try P256.KeyAgreement.PrivateKey(x963Representation: privateKeyData)
        let publicKeyString = try publicKey.toString(representation: .compressed)
        let privateKeyString = try privateKey.toString(representation: .raw)
        return TurnkeyClient(apiPrivateKey: privateKeyString,
                             apiPublicKey: publicKeyString)
    }

    func saveSession(userId: String,
                     organizationId: String,
                     encryptedBundle: String,
                     ephemeralPrivateKey: P256.KeyAgreement.PrivateKey,
                     expirationInSeconds: Int = 3600
    ) async throws -> TurnkeyClient? {
        let (decryptedPrivateKey, decryptedPublicKey) = try AuthManager.decryptBundle(
            encryptedBundle: encryptedBundle,
            ephemeralPrivateKey: ephemeralPrivateKey
        )
        let tempApiPublicKeyCompressed = try decryptedPublicKey.toString(
            representation: PublicKeyRepresentation
                .compressed)
        let tempApiPrivateKey = try decryptedPrivateKey.toString(
            representation: PrivateKeyRepresentation.raw)

        // Instantiate temporary TurnkeyClient using decrypted keys
        let tempClient = TurnkeyClient(apiPrivateKey: tempApiPrivateKey,
                                       apiPublicKey: tempApiPublicKeyCompressed)

        // Generate Secure Enclave key pair (new session key)
        let keyTag = try createKeypair()
        let (enclavePublicKeyData, _) = try publicPrivateKeyPair(for: keyTag)
        let enclavePublicKeyCompressed = try P256.Signing.PublicKey(
            x963Representation: enclavePublicKeyData
        )
        let enclavePublicKeyHex = try enclavePublicKeyCompressed.toString(representation: .compressed)

        // Create permanent API key via temporary client
        let apiKeyParams = [
            Components.Schemas.ApiKeyParamsV2(
                apiKeyName: "Session Key \(Int(Date().timeIntervalSince1970))",
                publicKey: enclavePublicKeyHex,
                curveType: .API_KEY_CURVE_P256,
                expirationSeconds: String(expirationInSeconds)
            )
        ]

        _ = try await tempClient.createApiKeys(
            organizationId: organizationId,
            apiKeys: apiKeyParams,
            userId: userId
        )

//        switch apiKeyCreationResponse {
//        case .ok(let apiKeyResponse):
//            print("Created API key: \(apiKeyResponse)")
//        case .undocumented(statusCode: let status, let payload):
//            if let body = payload.body {
//                let bodyString = try await String(collecting: body, upTo: .max)
//                print("apiKeyCreation bodyString: \(bodyString)")
//            }
//        }

        // Derive session expiration and persist session
        let sessionExpiry = Date().addingTimeInterval(TimeInterval(expirationInSeconds))
        let newSession = Session(
            keyTag: keyTag,
            expiresAt: sessionExpiry,
            userId: userId,
            organizationId: organizationId
        )

        try save(session: newSession)

        return try turnkeyClientFromActiveSession()
    }
}

extension TurnkeySessionManager {
    private func save(session: Session) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(session)

        // Query for existing item
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: sessionKey,
        ]

        // Attributes to update or add
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        // Attempt to update existing item
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            // If item not found, add new item
            var newItem = query
            newItem.merge(attributes) { _, new in new }
            let addStatus = SecItemAdd(newItem as CFDictionary, nil)
            if addStatus != errSecSuccess {
                throw NSError(domain: "SessionManager", code: Int(addStatus), userInfo: nil)
            }
        } else if status != errSecSuccess {
            throw NSError(domain: "SessionManager", code: Int(status), userInfo: nil)
        }
    }

    /// Loads the active session from the Keychain.
    public func loadActiveSession() throws -> Session? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: sessionKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        let decoder = JSONDecoder()
        let session = try decoder.decode(Session.self, from: data)
        // Check if session is still valid
        if session.expiresAt > Date() {
            return session
        } else {
            // Session expired – keep it so we can reuse IDs later.
            return nil
        }
    }
}

extension TurnkeySessionManager {
    private func createKeypair() throws -> String {
        let tag = "com.convos.ios.\(UUID().uuidString)"
        guard let tagData = tag.data(using: .utf8) else {
            throw TurnkeySessionManagerError.keyGenerationFailed(
                NSError(domain: "TagEncoding", code: -1))
        }

        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: tagData,
            ],
        ]

        var error: Unmanaged<CFError>?
        guard SecKeyCreateRandomKey(attributes as CFDictionary, &error) != nil else {
            throw TurnkeySessionManagerError.keyGenerationFailed(error!.takeRetainedValue() as Error)
        }
        return tag
    }

    /// Retrieves the public key (ANSI X9.63 representation) for a stored key.
    private func publicPrivateKeyPair(for tag: String) throws -> (Data, Data) {
        guard let tagData = tag.data(using: .utf8) else {
            throw TurnkeySessionManagerError.keyRetrievalFailed(errSecParam)
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrApplicationTag as String: tagData,
            kSecReturnRef as String: true,
        ]
        // Retrieve the SecKey reference as a CFTypeRef
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let item = item else {
            throw TurnkeySessionManagerError.keyRetrievalFailed(status)
        }
        // Force-cast the CFTypeRef to SecKey (guaranteed by SecItemCopyMatching)
        let privKey = item as! SecKey
        var error: Unmanaged<CFError>?
        guard let pubKey = SecKeyCopyPublicKey(privKey),
              let privateKey = SecKeyCopyExternalRepresentation(privKey, &error) as Data? else {
            Logger.error("Error extracting public/private key")
            throw TurnkeySessionManagerError.publicKeyExtractionFailed
        }
        guard let ext = SecKeyCopyExternalRepresentation(pubKey, &error) as Data? else {
            throw TurnkeySessionManagerError.externalRepresentationFailed
        }
        return (ext, privateKey)
    }
}

// swiftlint:enable force_cast force_unwrapping
