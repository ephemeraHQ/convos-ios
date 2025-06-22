import Combine
import Foundation
import XMTPiOS

protocol AuthServiceRegisteredResultType: AuthServiceResultType {
    var displayName: String { get }
    var inbox: any AuthServiceInboxType { get }
}

protocol AuthServiceResultType {
    var inboxes: [any AuthServiceInboxType] { get }
}

protocol AuthServiceInboxType {
    var providerId: String { get }
    var signingKey: any XMTPiOS.SigningKey { get }
    var databaseKey: Data { get }
}

struct AuthServiceRegisteredResult: AuthServiceRegisteredResultType {
    let displayName: String
    let inbox: any AuthServiceInboxType
    var inboxes: [any AuthServiceInboxType] { [inbox] }
}

struct AuthServiceResult: AuthServiceResultType {
    var inboxes: [any AuthServiceInboxType]
}

struct AuthServiceInbox: AuthServiceInboxType {
    let providerId: String
    let signingKey: any XMTPiOS.SigningKey
    let databaseKey: Data
}

enum AuthServiceState {
    case unknown,
         notReady,
         migrating(ConvosMigration),
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
    var authStatePublisher: AnyPublisher<AuthServiceState, Never> { get }

    func prepare() async throws

    func signIn() async throws
    func register(displayName: String) async throws
    func signOut() async throws
}
