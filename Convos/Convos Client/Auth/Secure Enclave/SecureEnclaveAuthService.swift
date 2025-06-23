import Combine
import Foundation
import XMTPiOS

class SecureEnclaveAuthService: AuthServiceProtocol {
    private let identityStore: SecureEnclaveIdentityStore = .init()
    private let authStateSubject: CurrentValueSubject<AuthServiceState, Never> = .init(.unknown)

    var state: AuthServiceState {
        authStateSubject.value
    }

    var authStatePublisher: AnyPublisher<AuthServiceState, Never> {
        authStateSubject.eraseToAnyPublisher()
    }

    func prepare() async throws {
        try refreshAuthState()
    }

    func signIn() async throws {}

    func signOut() async throws {}

    func register(displayName: String) async throws {
        let identity = try identityStore.save()
        authStateSubject.send(.registered(
            AuthServiceRegisteredResult(
                displayName: displayName,
                inbox: AuthServiceInbox(
                    type: .ephemeral,
                    provider: .local,
                    providerId: identity.id,
                    signingKey: identity.privateKey,
                    databaseKey: identity.databaseKey
                )
            )
        ))
    }

    func deleteAccount() async throws {
        try identityStore.delete()
        authStateSubject.send(.unauthorized)
    }

    // MARK: - Private Helpers

    private func refreshAuthState() throws {
        do {
            if let identity = try identityStore.load() {
                authStateSubject.send(.authorized(
                    AuthServiceResult(
                        inboxes: [
                            AuthServiceInbox(
                                type: .ephemeral,
                                provider: .local,
                                providerId: identity.id,
                                signingKey: identity.privateKey,
                                databaseKey: identity.databaseKey
                            )
                        ]
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
