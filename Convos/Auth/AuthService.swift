import Combine
import Foundation

enum AuthServiceState {
    case unknown, authorized, unauthorized
}

protocol AuthServiceProtocol {
    var state: AuthServiceState { get }

    func signIn() async throws
    func signOut() async throws

    func authStatePublisher() -> AnyPublisher<AuthServiceState, Never>
}

class AuthService: AuthServiceProtocol {
    var state: AuthServiceState {
        authStateSubject.value
    }

    private var authStateSubject: CurrentValueSubject<AuthServiceState, Never> = .init(.unknown)

    init() {
        authStateSubject.send(.unauthorized)
    }

    func signIn() async throws {
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

    private var authStateSubject: CurrentValueSubject<AuthServiceState, Never> = .init(.unknown)

    init() {
        authStateSubject.send(.unauthorized)
    }

    func signIn() async throws {
        authStateSubject.send(.authorized)
    }

    func signOut() async throws {
        authStateSubject.send(.unauthorized)
    }

    func authStatePublisher() -> AnyPublisher<AuthServiceState, Never> {
        return authStateSubject.eraseToAnyPublisher()
    }
}
