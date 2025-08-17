import Combine
import Foundation
import XMTPiOS

public class SecureEnclaveAuthService: LocalAuthServiceProtocol {
    private let identityStore: SecureEnclaveIdentityStore = .init()
    private let authStateSubject: CurrentValueSubject<AuthServiceState, Never> = .init(.unknown)

    public init() {}

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

    public func inboxId(for providerId: String) throws -> String {
        return try identityStore.loadInboxId(for: providerId)
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
}
