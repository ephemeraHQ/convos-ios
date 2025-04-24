import Foundation

extension KeychainItemProtocol {
    static var service: String {
        return "org.convos.ios"
    }
}

enum ConvosKeychainItem: String, KeychainItemProtocol {
    case jwt // temporary backend
    case convosJwt // convos backend
    case xmtpDatabaseKey

    var account: String {
        return rawValue
    }
}
