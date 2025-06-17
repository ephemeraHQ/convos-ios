import Combine
import Foundation
import XMTPiOS

class SecureEnclaveAuthService: AuthServiceProtocol {
    struct EnclaveAuthResult: AuthServiceResultType {
        let signingKey: SigningKey
        let databaseKey: Data
        let databaseDirectory: String
    }

    struct EnclaveRegisteredResult: AuthServiceRegisteredResultType {
        let displayName: String
        let signingKey: SigningKey
        let databaseKey: Data
        let databaseDirectory: String
    }

    private let environment: AppEnvironment
    private let identityStore: SecureEnclaveIdentityStore = .init()
    private let authStateSubject: CurrentValueSubject<AuthServiceState, Never> = .init(.unknown)

    var state: AuthServiceState {
        authStateSubject.value
    }

    var authStatePublisher: AnyPublisher<AuthServiceState, Never> {
        authStateSubject.eraseToAnyPublisher()
    }

    var supportsMultipleAccounts: Bool {
        false
    }

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    func prepare() async throws {
        try refreshAuthState()
    }

    func signIn() async throws {}

    func signOut() async throws {}

    func register(displayName: String) async throws {
        let identity = try identityStore.save()
        authStateSubject.send(.registered(
            EnclaveRegisteredResult(
                displayName: displayName,
                signingKey: identity.privateKey,
                databaseKey: identity.databaseKey,
                databaseDirectory: environment.defaultDatabasesDirectory
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
                    EnclaveAuthResult(
                        signingKey: identity.privateKey,
                        databaseKey: identity.databaseKey,
                        databaseDirectory: environment.defaultDatabasesDirectory
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
