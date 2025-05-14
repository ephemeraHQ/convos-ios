import Foundation

public extension ConvosSDK {
    protocol User {
        var id: String { get }
        var name: String { get }
        var walletAddress: String? { get }
        var chainId: Int64? { get }
        func sign(message: String) async throws -> Data?
    }
}
