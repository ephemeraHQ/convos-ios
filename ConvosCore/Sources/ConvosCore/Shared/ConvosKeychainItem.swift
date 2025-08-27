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

struct LastRegisteredPushTokenKeychainItem: KeychainItemProtocol {
    let inboxId: String

    var account: String {
        return "push-token-\(inboxId)"
    }
}

struct UnusedInboxKeychainItem: KeychainItemProtocol {
    static let account: String = "unused-inbox"

    var account: String {
        return Self.account
    }
}

struct BackendInitializedKeychainItem: KeychainItemProtocol {
    let inboxId: String

    var account: String {
        return "backend-init-\(inboxId)"
    }
}
