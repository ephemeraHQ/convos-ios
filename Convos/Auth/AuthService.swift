import Combine
import Foundation

enum AuthServiceState {
    case unknown, authorized, unauthorized
}

protocol AuthServiceProtocol {
    var state: AuthServiceState { get }
    var currentIdentity: CTUser? { get }
    var availableIdentities: [CTUser] { get }

    func signIn(with identity: CTUser) async throws
    func signOut() async throws

    func authStatePublisher() -> AnyPublisher<AuthServiceState, Never>
}

class AuthService: AuthServiceProtocol {
    var state: AuthServiceState {
        authStateSubject.value
    }

    var currentIdentity: CTUser? {
        identityStore.currentIdentity
    }

    var availableIdentities: [CTUser] {
        identityStore.availableIdentities
    }

    private var authStateSubject: CurrentValueSubject<AuthServiceState, Never> = .init(.unknown)
    private let identityStore: CTIdentityStore

    init(identityStore: CTIdentityStore) {
        self.identityStore = identityStore
        authStateSubject.send(identityStore.currentIdentity != nil ? .authorized : .unauthorized)
    }

    func signIn(with identity: CTUser) async throws {
        identityStore.switchIdentity(to: identity)
        authStateSubject.send(.authorized)
    }

    func signOut() async throws {
        authStateSubject.send(.unauthorized)
    }

    func authStatePublisher() -> AnyPublisher<AuthServiceState, Never> {
        return authStateSubject.eraseToAnyPublisher()
    }
}

class MockAuthService: AuthServiceProtocol {
    var state: AuthServiceState {
        authStateSubject.value
    }

    var currentIdentity: CTUser?
    var availableIdentities: [CTUser] = []

    private var authStateSubject: CurrentValueSubject<AuthServiceState, Never> = .init(.unknown)

    init() {
        authStateSubject.send(.unauthorized)
    }

    func signIn(with identity: CTUser) async throws {
        currentIdentity = identity
        authStateSubject.send(.authorized)
    }

    func signOut() async throws {
        currentIdentity = nil
        authStateSubject.send(.unauthorized)
    }

    func authStatePublisher() -> AnyPublisher<AuthServiceState, Never> {
        return authStateSubject.eraseToAnyPublisher()
    }
}
