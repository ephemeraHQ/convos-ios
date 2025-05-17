import Foundation

extension KeychainItemProtocol {
    static var service: String {
        return "org.convos.ios"
    }
}

enum ConvosKeychainItem: String, KeychainItemProtocol {
    case convosJwt // convos backend

    var account: String {
        return rawValue
    }
}
