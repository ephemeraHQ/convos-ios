import Foundation

actor MockKeychainIdentityStore: KeychainIdentityStoreProtocol {
    private var savedIdentities: [String: KeychainIdentity] = [:]

    func generateKeys() throws -> KeychainIdentityKeys {
        try KeychainIdentityKeys.generate()
    }

    func save(inboxId: String, clientId: String, keys: KeychainIdentityKeys) throws -> KeychainIdentity {
        let identity = KeychainIdentity(inboxId: inboxId, clientId: clientId, keys: keys)
        savedIdentities[inboxId] = identity
        return identity
    }

    func identity(for inboxId: String) throws -> KeychainIdentity {
        guard let identity = savedIdentities[inboxId] else {
            throw KeychainIdentityStoreError.identityNotFound("Identity not found for inboxId: \(inboxId)")
        }
        return identity
    }

    func identity(forClientId clientId: String) throws -> KeychainIdentity {
        guard let identity = savedIdentities.values.first(where: { $0.clientId == clientId }) else {
            throw KeychainIdentityStoreError.identityNotFound("Identity not found for clientId: \(clientId)")
        }
        return identity
    }

    func loadAll() throws -> [KeychainIdentity] {
        return Array(savedIdentities.values)
    }

    func delete(inboxId: String) throws {
        savedIdentities.removeValue(forKey: inboxId)
    }

    func deleteAll() throws {
        savedIdentities.removeAll()
    }
}
