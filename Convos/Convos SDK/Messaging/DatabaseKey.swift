import Foundation
import Security

struct DatabaseKey {
    let rawData: Data

    static func generate() throws -> DatabaseKey {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        let databaseKey = Data(bytes)
        return .init(rawData: databaseKey)
    }
}
