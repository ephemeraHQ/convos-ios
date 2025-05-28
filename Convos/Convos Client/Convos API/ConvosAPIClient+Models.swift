import Foundation
import UIKit

enum ConvosAPI {
    struct UserResponse: Decodable {
        let id: String
        let identities: [Identity]
        struct Identity: Decodable {
            let id: String
            let turnkeyAddress: String
            let xmtpId: String?
        }
    }

    struct CreateUserRequest: Encodable {
        let turnkeyUserId: String
        let device: Device
        let identity: Identity
        let profile: Profile
        struct Device: Encodable {
            let os: String
            let name: String?
        }
        struct Identity: Encodable {
            let turnkeyAddress: String
            let xmtpId: String?
            let xmtpInstallationId: String?
        }
        struct Profile: Encodable {
            let name: String
            let username: String
            let description: String?
            let avatar: String?
        }
    }

    struct CreatedUserResponse: Decodable {
        let id: String
        let turnkeyUserId: String
        let device: Device
        let identity: Identity
        let profile: Profile
        struct Device: Decodable {
            let id: String
            let os: String
            let name: String?
        }
        struct Identity: Decodable {
            let id: String
            let turnkeyAddress: String
            let xmtpId: String?
        }
        struct Profile: Decodable {
            let id: String
            let name: String
            let username: String
            let description: String?
            let avatar: String?
        }
    }

    struct UsernameCheckResponse: Decodable {
        let taken: Bool
    }

    struct ProfileResponse: Decodable {
        let id: String
        let name: String
        let username: String
        let description: String?
        let avatar: String?
        let xmtpId: String
        let turnkeyAddress: String
    }
}

extension ConvosAPI.CreateUserRequest.Device {
    static func current() -> Self {
        #if targetEnvironment(macCatalyst)
        let osString = "macos"
        #else
        let osString = "ios"
        #endif
        return .init(
            os: osString,
            name: UIDevice.current.name
        )
    }
}
