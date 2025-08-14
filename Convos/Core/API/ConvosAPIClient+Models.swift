import Foundation
import UIKit

enum ConvosAPI {
    enum AuthenticatorTransport: String, Codable {
        case ble = "AUTHENTICATOR_TRANSPORT_BLE"
        case transportInternal = "AUTHENTICATOR_TRANSPORT_INTERNAL"
        case nfc = "AUTHENTICATOR_TRANSPORT_NFC"
        case usb = "AUTHENTICATOR_TRANSPORT_USB"
        case hybrid = "AUTHENTICATOR_TRANSPORT_HYBRID"
    }

    struct PasskeyAttestation: Codable {
        let credentialId: String
        let clientDataJson: String
        let attestationObject: String
        let transports: [AuthenticatorTransport]
    }

    struct Passkey: Codable {
        let challenge: String
        let attestation: PasskeyAttestation
    }

    struct FetchJwtResponse: Codable {
        let token: String
    }

    struct CreateSubOrganizationResponse: Codable {
        let subOrgId: String
        let walletAddress: String
    }

    struct UserResponse: Decodable {
        let id: String
        let identities: [Identity]
        struct Identity: Decodable {
            let id: String
            let identityAddress: String?
            let xmtpId: String
        }
    }

    struct CreateUserRequest: Encodable {
        let userId: String
        let userType: UserType
        let device: Device
        let identity: Identity
        let profile: Profile

        enum UserType: String, Encodable {
            case onDevice
            case turnkey
        }
        struct Device: Encodable {
            let os: String
            let name: String?
            let id: String
        }
        struct Identity: Encodable {
            let identityAddress: String?
            let xmtpId: String
            let xmtpInstallationId: String?
        }
        struct Profile: Encodable {
            let name: String?
            let username: String?
            let description: String?
            let avatar: String?
        }
    }

    struct CreateInviteRequest: Encodable {
        let groupId: String
        let name: String?
        let description: String?
        let imageUrl: String?
        let maxUses: Int?
        let expiresAt: Date?
        let autoApprove: Bool = false
        let notificationTargets: [String] = []
    }

    struct UpdateProfileRequest: Encodable {
        let name: String?
        let username: String?
        let description: String?
        let avatar: String?

        init(name: String? = nil, username: String? = nil, description: String? = nil, avatar: String? = nil) {
            self.name = name
            self.username = username
            self.description = description
            self.avatar = avatar
        }
    }

    struct UpdateProfileResponse: Decodable {
        let id: String
        let name: String?
        let username: String?
        let description: String?
        let avatar: String?
        let createdAt: String
        let updatedAt: String
    }

    enum InviteCodeStatus: String, Decodable {
        case active = "ACTIVE",
             expired = "EXPIRED",
             disabled = "DISABLED"
    }

    struct InviteDetailsResponse: Decodable {
        let id: String
        let name: String?
        let description: String?
        let imageUrl: String?
        let maxUses: Int?
        let usesCount: Int
        let status: InviteCodeStatus
        let expiresAt: Date?
        let autoApprove: Bool
        let groupId: String
        let createdAt: Date
        let inviteLinkURL: String
    }

    struct PublicInviteDetailsResponse: Decodable {
        let id: String
        let name: String?
        let description: String?
        let imageUrl: String?
        let inviteLinkURL: String
    }

    struct CreatedUserResponse: Decodable {
        let id: String
        let userId: String
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
            let identityAddress: String?
            let xmtpId: String?
        }
        struct Profile: Decodable {
            let id: String
            let name: String?
            let description: String?
            let avatar: String?
        }
    }

    struct UsernameCheckResponse: Decodable {
        let taken: Bool
    }

    struct BatchProfilesResponse: Decodable {
        let profiles: [String: ProfileResponse]
    }

    struct ProfileResponse: Decodable {
        let id: String
        let name: String?
        let username: String?
        let description: String?
        let avatar: String?
        let xmtpId: String
        let identityAddress: String?
    }

    // MARK: - Device Update Models

    struct DeviceUpdateRequest: Codable {
        let pushToken: String
        let pushTokenType: DeviceUpdatePushTokenType
        let apnsEnv: DeviceUpdateApnsEnvironment

        enum DeviceUpdatePushTokenType: String, Codable {
            case apns
        }

        enum DeviceUpdateApnsEnvironment: String, Codable {
            case sandbox
            case production
        }

        init(pushToken: String,
             pushTokenType: DeviceUpdatePushTokenType = .apns,
             apnsEnv: DeviceUpdateApnsEnvironment) {
            self.pushToken = pushToken
            self.pushTokenType = pushTokenType
            self.apnsEnv = apnsEnv
        }
    }

    struct DeviceUpdateResponse: Codable {
        let id: String
        let pushToken: String?
        let pushTokenType: String
        let apnsEnv: String?
        let updatedAt: String
        let pushFailures: Int
    }
}

extension ConvosAPI.CreateUserRequest.Device {
    static func current() -> Self {
        return .init(
            os: DeviceInfo.osString,
            name: nil,
            id: DeviceInfo.deviceIdentifier
        )
    }
}
