import Foundation

struct ConvosUser: ConvosSDK.User {
    var id: String {
        "1"
    }

    var chainId: Int64? {
        0
    }

    var publicIdentifier: String? {
        ""
    }
}

extension ConvosUser {
    func sign(message: String) async throws -> Data? {
        return nil
    }
}
