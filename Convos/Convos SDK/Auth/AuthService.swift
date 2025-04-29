import Combine
import Foundation

public extension ConvosSDK {
    enum AuthServiceState {
        case unknown, notReady, authorized(ConvosSDK.User), unauthorized
    }

    protocol AuthServiceProtocol {
        var state: AuthServiceState { get }
        var currentUser: User? { get }

        var messagingService: MessagingServiceProtocol { get }

        func prepare() async throws

        func signIn() async throws
        func register(displayName: String) async throws
        func signOut() async throws

        func authStatePublisher() -> AnyPublisher<AuthServiceState, Never>
    }
}

struct MockUser: ConvosSDK.User {
    var id: String = "mock-id"
    var chainId: Int64? = 1
    var publicIdentifier: String? = "mock-public-id"
    func sign(message: String) async throws -> Data? {
        Data()
    }
}

class MockAuthService: ConvosSDK.AuthServiceProtocol {
    let mockUser: MockUser = .init()

    var currentUser: ConvosSDK.User? {
        mockUser
    }

    var state: ConvosSDK.AuthServiceState {
        authStateSubject.value
    }

    var messagingService: any ConvosSDK.MessagingServiceProtocol {
        MockMessagingService()
    }

    private var authStateSubject: CurrentValueSubject<ConvosSDK.AuthServiceState, Never> = .init(.unknown)

    init() {
        authStateSubject.send(.unauthorized)
    }

    func prepare() async throws {
        authStateSubject.send(.unknown)
    }

    func signIn() async throws {
        authStateSubject.send(.authorized(mockUser))
    }

    func register(displayName: String) async throws {
        authStateSubject.send(.authorized(mockUser))
    }

    func signOut() async throws {
        authStateSubject.send(.unauthorized)
    }

    func authStatePublisher() -> AnyPublisher<ConvosSDK.AuthServiceState, Never> {
        return authStateSubject.eraseToAnyPublisher()
    }
}
