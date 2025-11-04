import Foundation

extension KeychainItemProtocol {
    static var service: String {
        return "org.convos.ios.KeychainItemProtocol.v2"
    }
}

struct ConvosJWTKeychainItem: KeychainItemProtocol {
    let deviceId: String

    var account: String {
        return deviceId
    }
}

struct UnusedInboxKeychainItem: KeychainItemProtocol {
    static let account: String = "unused-inbox"

    var account: String {
        return Self.account
    }
}
