import Foundation

extension ConvosAPI.CreateUserRequest.Profile {
    static var empty: Self {
        .init(name: nil, username: nil, description: nil, avatar: nil)
    }
}

public enum ConvosAPI {
    public enum AuthenticatorTransport: String, Codable {
        case ble = "AUTHENTICATOR_TRANSPORT_BLE"
        case transportInternal = "AUTHENTICATOR_TRANSPORT_INTERNAL"
        case nfc = "AUTHENTICATOR_TRANSPORT_NFC"
        case usb = "AUTHENTICATOR_TRANSPORT_USB"
        case hybrid = "AUTHENTICATOR_TRANSPORT_HYBRID"
    }

    public struct PasskeyAttestation: Codable {
        public let credentialId: String
        public let clientDataJson: String
        public let attestationObject: String
        public let transports: [AuthenticatorTransport]
    }

    public struct Passkey: Codable {
        public let challenge: String
        public let attestation: PasskeyAttestation
    }

    public struct FetchJwtResponse: Codable {
        public let token: String
    }

    public struct CreateSubOrganizationResponse: Codable {
        public let subOrgId: String
        public let walletAddress: String
    }

    public struct UserResponse: Decodable {
        public let id: String
        public let identities: [Identity]
        public struct Identity: Decodable {
            public let id: String
            public let identityAddress: String?
            public let xmtpId: String
        }
    }

    public struct CreateUserRequest: Encodable {
        public let userId: String
        public let userType: UserType
        public let device: Device
        public let identity: Identity
        public let profile: Profile

        public enum UserType: String, Encodable {
            case onDevice
            case turnkey
        }
        public struct Device: Encodable {
            public let os: String
            public let name: String?
            public let id: String
        }
        public struct Identity: Encodable {
            public let identityAddress: String?
            public let xmtpId: String
            public let xmtpInstallationId: String?
        }
        public struct Profile: Encodable {
            public let name: String?
            public let username: String?
            public let description: String?
            public let avatar: String?
        }
    }

    public struct CreateInviteCode: Encodable {
        public let groupId: String
        public let name: String?
        public let description: String?
        public let imageUrl: String?
        public let maxUses: Int?
        public let expiresAt: Date?
        public let autoApprove: Bool
        public let notificationTargets: [String]
    }

    public struct RequestToJoinResponse: Decodable {
        public let id: String
        public let invite: InviteDetailsResponse
        public let createdAt: String
    }

    public struct DeleteRequestToJoinResponse: Decodable {
        public let id: String
        public let deleted: Bool
    }

    public struct UpdateProfileRequest: Encodable {
        public let name: String?
        public let username: String?
        public let description: String?
        public let avatar: String?

        public init(name: String? = nil, username: String? = nil, description: String? = nil, avatar: String? = nil) {
            self.name = name
            self.username = username
            self.description = description
            self.avatar = avatar
        }
    }

    public struct UpdateProfileResponse: Decodable {
        public let id: String
        public let name: String?
        public let username: String?
        public let description: String?
        public let avatar: String?
        public let createdAt: String
        public let updatedAt: String
    }

    public enum InviteCodeStatus: String, Decodable {
        case active = "ACTIVE",
             expired = "EXPIRED",
             disabled = "DISABLED"
    }

    public struct InviteDetailsResponse: Decodable {
        public let id: String
        public let name: String?
        public let description: String?
        public let imageUrl: String?
        public let maxUses: Int?
        public let usesCount: Int
        public let status: InviteCodeStatus
        public let expiresAt: Date?
        public let autoApprove: Bool
        public let groupId: String
        public let createdAt: Date
        public let inviteLinkURL: String
    }

    public struct InviteDetailsWithGroupResponse: Decodable {
        public let id: String
        public let name: String?
        public let description: String?
        public let imageUrl: String?
        public let inviteLinkURL: String
        public let groupId: String
        public let inviterInboxId: String
    }

    public struct PublicInviteDetailsResponse: Decodable {
        public let id: String
        public let name: String?
        public let description: String?
        public let imageUrl: String?
        public let inviteLinkURL: String
    }

    public struct CreatedUserResponse: Decodable {
        public let id: String
        public let userId: String
        public let device: Device
        public let identity: Identity
        public let profile: Profile
        public struct Device: Decodable {
            public let id: String
            public let os: String
            public let name: String?
        }
        public struct Identity: Decodable {
            public let id: String
            public let identityAddress: String?
            public let xmtpId: String?
        }
        public struct Profile: Decodable {
            public let id: String
            public let name: String?
            public let description: String?
            public let avatar: String?
        }
    }

    public struct UsernameCheckResponse: Decodable {
        public let taken: Bool
    }

    public struct BatchProfilesResponse: Decodable {
        public let profiles: [String: ProfileResponse]
    }

    public struct ProfileResponse: Decodable {
        public let id: String
        public let name: String?
        public let username: String?
        public let description: String?
        public let avatar: String?
        public let xmtpId: String
        public let identityAddress: String?
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

    public struct DeviceUpdateResponse: Codable {
        public let id: String
        public let pushToken: String?
        public let pushTokenType: String
        public let apnsEnv: String?
        public let updatedAt: String
        public let pushFailures: Int
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
