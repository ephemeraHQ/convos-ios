import Combine
import Foundation
import XMTPiOS

public extension ConvosSDK {
    protocol RegisteredResultType: AuthorizedResultType {
        var displayName: String { get }
    }

    protocol AuthorizedResultType {
        var signingKey: any XMTPiOS.SigningKey { get }
        var databaseKey: Data { get }
    }

    enum AuthServiceState {
        case unknown,
             notReady,
             registered(RegisteredResultType),
             authorized(AuthorizedResultType),
             unauthorized

        var isAuthenticated: Bool {
            switch self {
            case .authorized, .registered:
                return true
            default: return false
            }
        }

        var authorizedResult: AuthorizedResultType? {
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

        func prepare() async throws

        func signIn() async throws
        func register(displayName: String) async throws
        func signOut() async throws

        func authStatePublisher() -> AnyPublisher<AuthServiceState, Never>
    }
}
