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
    var type: InboxType { get }
    var provider: InboxProvider { get }
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
    let type: InboxType
    let provider: InboxProvider
    let providerId: String
    let signingKey: any XMTPiOS.SigningKey
    let databaseKey: Data
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

protocol BaseAuthServiceProtocol {
    var state: AuthServiceState { get }
    var authStatePublisher: AnyPublisher<AuthServiceState, Never> { get }

    func prepare() throws
}

protocol AuthServiceProtocol: BaseAuthServiceProtocol {
    var accountsService: (any AuthAccountsServiceProtocol)? { get }

    func signIn() async throws
    func register(displayName: String) async throws
    func signOut() async throws
}

protocol LocalAuthServiceProtocol: BaseAuthServiceProtocol {
    func register(displayName: String, inboxType: InboxType) throws -> any AuthServiceRegisteredResultType
    func deleteAll() throws
}
