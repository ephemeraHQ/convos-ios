import Foundation

struct DatabaseKey: KeychainItemProtocol {
    let account: String
    let value: String

    var valueData: Data? {
        Data(base64Encoded: value)
    }

    static func generate(for user: ConvosSDK.User) -> DatabaseKey {
        let databaseKey = Data((0 ..< 32)
            .map { _ in UInt8.random(in: UInt8.min ... UInt8.max) })
        let value = databaseKey.base64EncodedString()
        return .init(account: user.id, value: value)
    }
}

extension KeychainService where T == DatabaseKey {
    func save(_ databaseKey: DatabaseKey) async throws {
        try save(databaseKey.value, for: databaseKey)
    }

    func retrieveKey(for user: ConvosSDK.User) throws -> DatabaseKey? {
        let account = user.id
        guard let value = try retrieve(service: DatabaseKey.service, account: account) else {
            return nil
        }
        return .init(account: account, value: value)
    }

    func delete(for user: ConvosSDK.User) throws {
        try delete(service: DatabaseKey.service, account: user.id)
    }
}
