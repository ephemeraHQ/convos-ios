import Foundation
import GRDB

protocol UserWriter {
    func storeUser(_ user: ConvosAPIClient.UserResponse) async throws
    func storeUser(_ user: ConvosAPIClient.CreatedUserResponse) async throws
}

class GRDBUserWriter: UserWriter {
    func storeUser(_ user: ConvosAPIClient.UserResponse) async throws {
    }

    func storeUser(_ user: ConvosAPIClient.CreatedUserResponse) async throws {
    }
}
