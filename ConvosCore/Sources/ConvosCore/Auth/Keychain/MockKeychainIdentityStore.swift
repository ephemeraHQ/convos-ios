import Foundation

actor MockKeychainIdentityStore: KeychainIdentityStoreProtocol {
    private var savedIdentity: KeychainIdentity?

    func generateKeys() throws -> KeychainIdentityKeys {
        try KeychainIdentityKeys.generate()
    }

    func save(inboxId: String, keys: KeychainIdentityKeys) throws -> KeychainIdentity {
        let identity = KeychainIdentity(inboxId: inboxId, keys: keys)
        savedIdentity = identity
        return identity
    }

    func identity() throws -> KeychainIdentity {
        guard let identity = savedIdentity else {
            throw KeychainIdentityStoreError.identityNotFound("Identity not set")
        }
        return identity
    }

    func delete() throws {
        savedIdentity = nil
    }
}
