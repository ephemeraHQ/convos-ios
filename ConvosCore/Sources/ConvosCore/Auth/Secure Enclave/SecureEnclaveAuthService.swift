import Combine
import Foundation
import XMTPiOS

public class SecureEnclaveAuthService: LocalAuthServiceProtocol {
    private let identityStore: SecureEnclaveIdentityStore
    private let authStateSubject: CurrentValueSubject<AuthServiceState, Never> = .init(.unknown)

    public init(accessGroup: String? = nil) {
        self.identityStore = SecureEnclaveIdentityStore(accessGroup: accessGroup)
    }

    public var state: AuthServiceState {
        authStateSubject.value
    }

    public var authStatePublisher: AnyPublisher<AuthServiceState, Never> {
        authStateSubject.eraseToAnyPublisher()
    }

    public func prepare() throws {
        try refreshAuthState()
    }

    public func register(displayName: String? = nil) throws -> any AuthServiceRegisteredResultType {
        let inboxType: InboxType = .ephemeral
        let identity = try identityStore.save(type: inboxType)
        let result = AuthServiceRegisteredResult(
            displayName: displayName,
            inbox: AuthServiceInbox(
                type: inboxType,
                provider: .local,
                providerId: identity.id,
                signingKey: identity.privateKey,
                databaseKey: identity.databaseKey
            )
        )
        authStateSubject.send(.registered(result))
        return result
    }

    public func deleteAccount(with providerId: String) throws {
        try identityStore.delete(for: providerId)
        try refreshAuthState()
    }

    public func deleteAll() throws {
        let identities = try identityStore.loadAll()
        try identities.forEach { try identityStore.delete(for: $0.id) }
        try refreshAuthState()
    }

        public func save(inboxId: String, for providerId: String) throws {
        try identityStore.save(inboxId: inboxId, for: providerId)
    }

    public func saveProviderIdMapping(providerId: String, for inboxId: String) throws {
        try identityStore.save(providerId: providerId, for: inboxId)
    }

    public func inboxId(for providerId: String) throws -> String {
        return try identityStore.loadInboxId(for: providerId)
    }

    public func inbox(for inboxId: String) throws -> (any AuthServiceInboxType)? {
        let providerId = try identityStore.loadProviderId(for: inboxId)
        guard let identity = try identityStore.load(for: providerId) else {
            return nil
        }
        return AuthServiceInbox(
            type: identity.type,
            provider: .local,
            providerId: identity.id,
            signingKey: identity.privateKey,
            databaseKey: identity.databaseKey
        )
    }

    // MARK: - Private Helpers

    private func refreshAuthState() throws {
        let identities = try identityStore.loadAll()
        if identities.isEmpty {
            authStateSubject.send(.unauthorized)
            return
        }

        let inboxes: [AuthServiceInbox] = identities.map { identity in
            AuthServiceInbox(
                type: identity.type,
                provider: .local,
                providerId: identity.id,
                signingKey: identity.privateKey,
                databaseKey: identity.databaseKey
            )
        }

        let result = AuthServiceResult(inboxes: inboxes)
        authStateSubject.send(.authorized(result))
    }

    // MARK: - Debug/Development Methods

    /// Debug method to list all provider ID mappings
    public func debugListAllProviderIdMappings() {
        identityStore.debugListAllProviderIdMappings()
    }

    /// Debug method to re-save provider ID mappings for existing identities
    public func debugReSaveProviderIdMappings() {
        Logger.info("🔄 Re-saving provider ID mappings for existing identities")
        do {
            let identities = try identityStore.loadAll()
            for identity in identities {
                // We need to find the inbox ID for this provider ID
                // Let's look for {providerId}.inboxId entries
                do {
                    let inboxId = try identityStore.loadInboxId(for: identity.id)
                    Logger.info("Re-saving mapping: \(inboxId) → \(identity.id)")
                    try saveProviderIdMapping(providerId: identity.id, for: inboxId)
                } catch {
                    Logger.error("Failed to re-save mapping for provider \(identity.id): \(error)")
                }
            }
        } catch {
            Logger.error("Failed to load identities: \(error)")
        }
    }

    /// WARNING: This will delete ALL keychain data. Use only for debugging/development.
    /// Call this method temporarily to clear keychain data when testing keychain access group changes.
    public func debugWipeAllKeychainData() {
        identityStore.debugWipeAllKeychainData()
    }
}
