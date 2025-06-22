import Foundation

extension KeychainItemProtocol {
    static var service: String {
        return "org.convos.ios"
    }
}

struct ConvosJWTKeychainItem: KeychainItemProtocol {
    let inboxId: String

    var account: String {
        return inboxId
    }
}
