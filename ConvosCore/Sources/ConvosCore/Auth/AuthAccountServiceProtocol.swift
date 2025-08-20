import Foundation

public protocol AuthAccountsServiceProtocol {
    func addAccount(displayName: String) async throws -> any AuthServiceRegisteredResultType
}
