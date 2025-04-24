import Foundation

struct DatabaseKey {
    let value: String

    var valueData: Data? {
        Data(base64Encoded: value)
    }

    static func generate(for user: ConvosSDK.User) -> DatabaseKey {
        let databaseKey = Data((0 ..< 32)
            .map { _ in UInt8.random(in: UInt8.min ... UInt8.max) })
        let value = databaseKey.base64EncodedString()
        return .init(value: value)
    }
}
