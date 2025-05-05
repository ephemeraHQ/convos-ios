import Foundation

struct ConvosUser: ConvosSDK.User {
    let id: String
    let name: String

    var chainId: Int64? {
        0
    }

    var publicIdentifier: String? {
        ""
    }
}

extension ConvosUser: Hashable {}

extension ConvosUser {
    func sign(message: String) async throws -> Data? {
        return nil
    }
}
