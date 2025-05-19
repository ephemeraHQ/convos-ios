import Combine
import Foundation
import LocalAuthentication
import XMTPiOS

class SecureEnclaveAuthService: ConvosSDK.AuthServiceProtocol {
    struct EnclaveAuthResult: ConvosSDK.AuthorizedResultType {
        let signingKey: SigningKey
        let databaseKey: Data
    }

    struct EnclaveRegisteredResult: ConvosSDK.RegisteredResultType {
        let displayName: String
        let signingKey: SigningKey
        let databaseKey: Data
    }

    enum SecureEnclaveAuthServiceError: Error {
        case biometryNotAvailable,
             biometryAuthenticationFailed,
             keyTagMismatch
    }

    private let identityStore: SecureEnclaveIdentityStore = .init()
    private let authStateSubject: CurrentValueSubject<ConvosSDK.AuthServiceState, Never> = .init(.unknown)

    var state: ConvosSDK.AuthServiceState {
        authStateSubject.value
    }

    func prepare() async throws {
        try refreshAuthState()
    }

    func signIn() async throws {}

    func register(displayName: String) async throws {
        let identity = try identityStore.save()
        authStateSubject.send(.registered(EnclaveRegisteredResult(displayName: displayName,
                                                                  signingKey: identity.privateKey,
                                                                  databaseKey: identity.databaseKey)))
    }

    func signOut() async throws {
        try identityStore.delete()
        authStateSubject.send(.unauthorized)
    }

    func authStatePublisher() -> AnyPublisher<ConvosSDK.AuthServiceState, Never> {
        authStateSubject.eraseToAnyPublisher()
    }

    // MARK: - Private Helpers

    private func refreshAuthState() throws {
        do {
            if let identity = try identityStore.load() {
                authStateSubject.send(.authorized(EnclaveAuthResult(
                    signingKey: identity.privateKey,
                    databaseKey: identity.databaseKey
                )))
            } else {
                authStateSubject.send(.unauthorized)
            }
        } catch {
            authStateSubject.send(.unauthorized)
        }
    }
}
