import Foundation

protocol AuthAccountsServiceProtocol {
    func addAccount(displayName: String) async throws -> any AuthServiceRegisteredResultType
}
