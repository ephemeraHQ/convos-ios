import Combine
import Foundation
import XMTPiOS

protocol AuthServiceRegisteredResultType: AuthServiceResultType {
    var displayName: String { get }
}

protocol AuthServiceResultType {
    var signingKey: any XMTPiOS.SigningKey { get }
    var databaseKey: Data { get }
}

enum AuthServiceState {
    case unknown,
         notReady,
         registered(AuthServiceRegisteredResultType),
         authorized(AuthServiceResultType),
         unauthorized

    var isAuthenticated: Bool {
        switch self {
        case .authorized, .registered:
            return true
        default: return false
        }
    }

    var authorizedResult: AuthServiceResultType? {
        switch self {
        case .authorized(let result):
            return result
        case .registered(let result):
            return result
        default:
            return nil
        }
    }
}

protocol AuthServiceProtocol {
    var state: AuthServiceState { get }
    var supportsMultipleAccounts: Bool { get }

    func prepare() async throws

    func signIn() async throws
    func register(displayName: String) async throws
    func signOut() async throws

    func authStatePublisher() -> AnyPublisher<AuthServiceState, Never>
}

extension AuthServiceProtocol {
    var supportsMultipleAccounts: Bool { true }
}
