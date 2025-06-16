import Foundation
import LocalAuthentication
import Security

class TurnkeyDatabaseKeyStore: SecureEnclaveKeyStore {
    static let shared: TurnkeyDatabaseKeyStore = .init()
    internal let keychainService: String = "com.convos.ios.TurnkeyDatabaseKeyStore"

    private init() {}

    func databaseKey(for userId: String) throws -> Data {
        if let databaseKey = try loadDatabaseKey(for: userId) {
            return databaseKey
        } else {
            return try generateAndSaveDatabaseKey(for: userId)
        }
    }
}
