import Combine
import Foundation
import XMTPiOS

class SecureEnclaveAuthService: LocalAuthServiceProtocol {
    private let identityStore: SecureEnclaveIdentityStore = .init()
    private let authStateSubject: CurrentValueSubject<AuthServiceState, Never> = .init(.unknown)

    var state: AuthServiceState {
        authStateSubject.value
    }

    var authStatePublisher: AnyPublisher<AuthServiceState, Never> {
        authStateSubject.eraseToAnyPublisher()
    }

    func prepare() throws {
        try refreshAuthState()
    }

    func register(displayName: String) throws -> any AuthServiceRegisteredResultType {
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

    func deleteAll() throws {
        let identities = try identityStore.loadAll()
        try identities.forEach { try identityStore.delete(for: $0.id) }
    }

    // MARK: - Private Helpers

    private func refreshAuthState() throws {
        do {
            let identities = try identityStore.loadAll()
            if !identities.isEmpty {
                let inboxes: [AuthServiceInbox] = identities.map { identity in
                    AuthServiceInbox(
                        type: identity.type,
                        provider: .local,
                        providerId: identity.id,
                        signingKey: identity.privateKey,
                        databaseKey: identity.databaseKey
                    )
                }
                authStateSubject.send(.authorized(
                    AuthServiceResult(
                        inboxes: inboxes
                    )
                ))
            } else {
                authStateSubject.send(.unauthorized)
            }
        } catch {
            authStateSubject.send(.unauthorized)
        }
    }
}
