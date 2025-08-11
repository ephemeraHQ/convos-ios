import Foundation

class MockAPIClientFactory: ConvosAPIClientFactoryType {
    static func client(environment: AppEnvironment) -> any ConvosAPIBaseProtocol {
        MockBaseAPIClient()
    }

    static func authenticatedClient(
        client: any XMTPClientProvider,
        environment: AppEnvironment
    ) -> any ConvosAPIClientProtocol {
        MockAPIClient(client: client)
    }
}

enum MockAPIError: Error {
    case invalidURL
}

class MockBaseAPIClient: ConvosAPIBaseProtocol {
    func createSubOrganization(
        ephemeralPublicKey: String,
        passkey: ConvosAPI.Passkey
    ) async throws -> ConvosAPI.CreateSubOrganizationResponse {
        .init(subOrgId: UUID().uuidString, walletAddress: UUID().uuidString)
    }

    func request(for path: String, method: String, queryParameters: [String: String]?) throws -> URLRequest {
        guard let url = URL(string: "http://example.com") else {
            throw MockAPIError.invalidURL
        }
        return URLRequest(url: url)
    }
}

class MockAPIClient: MockBaseAPIClient, ConvosAPIClientProtocol {
    func getDevice(userId: String, deviceId: String) async throws -> ConvosAPI.DeviceUpdateResponse {
        return ConvosAPI.DeviceUpdateResponse(
            id: deviceId,
            pushToken: "existing-push-token",
            pushTokenType: "apns",
            apnsEnv: "sandbox",
            updatedAt: Date().ISO8601Format(),
            pushFailures: 0
        )
    }

    func updateDevicePushToken(userId: String, deviceId: String, pushToken: String) async throws -> ConvosAPI.DeviceUpdateResponse {
        return ConvosAPI.DeviceUpdateResponse(
            id: deviceId,
            pushToken: pushToken,
            pushTokenType: "apns",
            apnsEnv: "sandbox",
            updatedAt: Date().ISO8601Format(),
            pushFailures: 0
        )
    }

    func publicInviteDetails(_ inviteId: String) async throws -> ConvosAPI.PublicInviteDetailsResponse {
        .init(id: "invite_123", name: "My Invite", description: "My fun group chat", imageUrl: nil, inviteLinkURL: "http://convos.org/invite/123456")
    }

    var identifier: String {
        "\(client.inboxId)\(client.installationId)"
    }

    let client: any XMTPClientProvider

    init(client: any XMTPClientProvider) {
        self.client = client
        super.init()
    }

    func authenticate(inboxId: String, installationId: String, signature: String) async throws -> String {
        return "mock-jwt-token"
    }

    func getUser() async throws -> ConvosAPI.UserResponse {
        return ConvosAPI.UserResponse(
            id: "user_123",
            identities: [
                ConvosAPI.UserResponse.Identity(
                    id: "identity_1",
                    identityAddress: "0xMOCKADDRESS1",
                    xmtpId: "mock-xmtp-id"
                )
            ]
        )
    }

    func createUser(_ requestBody: ConvosAPI.CreateUserRequest) async throws -> ConvosAPI.CreatedUserResponse {
        return ConvosAPI.CreatedUserResponse(
            id: "created_user_123",
            userId: requestBody.userId,
            device: ConvosAPI.CreatedUserResponse.Device(
                id: "device_1",
                os: requestBody.device.os,
                name: requestBody.device.name
            ),
            identity: ConvosAPI.CreatedUserResponse.Identity(
                id: "identity_1",
                identityAddress: requestBody.identity.identityAddress,
                xmtpId: requestBody.identity.xmtpId
            ),
            profile: ConvosAPI.CreatedUserResponse.Profile(
                id: "profile_1",
                name: requestBody.profile.name,
                description: requestBody.profile.description,
                avatar: requestBody.profile.avatar
            )
        )
    }

    func createInvite(_ requestBody: ConvosAPI.CreateInviteRequest) async throws -> ConvosAPI.InviteDetailsResponse {
        return ConvosAPI
            .InviteDetailsResponse(
                id: "created_invite_123",
                name: "My Group",
                description: nil,
                imageUrl: nil,
                maxUses: nil,
                usesCount: 0,
                status: .active,
                expiresAt: nil,
                autoApprove: false,
                groupId: "my_group_123",
                createdAt: Date(),
                inviteLinkURL: "http://convos.org/invite/my_group_123"
            )
    }

    func inviteDetails(_ inviteId: String) async throws -> ConvosAPI.InviteDetailsResponse {
        return ConvosAPI
            .InviteDetailsResponse(
                id: "created_invite_123",
                name: "My Group",
                description: nil,
                imageUrl: nil,
                maxUses: nil,
                usesCount: 0,
                status: .active,
                expiresAt: nil,
                autoApprove: false,
                groupId: "my_group_123",
                createdAt: Date(),
                inviteLinkURL: "http://convos.org/invite/my_group_123"
            )
    }

    func checkUsername(_ username: String) async throws -> ConvosAPI.UsernameCheckResponse {
        return ConvosAPI.UsernameCheckResponse(taken: username == "takenusername")
    }

    func updateProfile(
        inboxId: String,
        with requestBody: ConvosAPI.UpdateProfileRequest
    ) async throws -> ConvosAPI.UpdateProfileResponse {
        .init(
            id: "",
            name: requestBody.name ?? "",
            username: requestBody.username ?? "",
            description: nil,
            avatar: requestBody.avatar,
            createdAt: Date().ISO8601Format(),
            updatedAt: Date().ISO8601Format()
        )
    }

    func getProfile(inboxId: String) async throws -> ConvosAPI.ProfileResponse {
        return ConvosAPI.ProfileResponse(
            id: inboxId,
            name: "Mock User",
            username: "mockuser",
            description: "This is a mock profile.",
            avatar: nil,
            xmtpId: "mock-xmtp-id",
            identityAddress: "0xMOCKADDRESS1"
        )
    }

    func getProfiles(for inboxIds: [String]) async throws -> ConvosAPI.BatchProfilesResponse {
        let profilesById: [String: ConvosAPI.ProfileResponse] = inboxIds.reduce(into: [:]) { result, id in
            let profile = ConvosAPI.ProfileResponse(
                id: id,
                name: "Mock User \(id)",
                username: "mockuser\(id)",
                description: "This is a mock profile for \(id).",
                avatar: nil,
                xmtpId: "mock-xmtp-id-\(id)",
                identityAddress: "0xMOCKADDRESS\(id)"
            )
            result[id] = profile
        }
        return ConvosAPI.BatchProfilesResponse(
            profiles: profilesById
        )
    }

    func getProfiles(matching query: String) async throws -> [ConvosAPI.ProfileResponse] {
        return [
            ConvosAPI.ProfileResponse(
                id: "search_1",
                name: "Search Result 1",
                username: "searchuser1",
                description: "Profile matching query: \(query)",
                avatar: nil,
                xmtpId: "mock-xmtp-id-search1",
                identityAddress: "0xMOCKADDRESSSEARCH1"
            )
        ]
    }

    func uploadAttachment(
        data: Data,
        filename: String,
        contentType: String,
        acl: String
    ) async throws -> String {
        return "https://mock-api.example.com/uploads/\(filename)"
    }

    func uploadAttachmentAndExecute(
        data: Data,
        filename: String,
        afterUpload: @escaping (String) async throws -> Void
    ) async throws -> String {
        let uploadedURL = "https://mock-api.example.com/uploads/\(filename)"
        try await afterUpload(uploadedURL)
        return uploadedURL
    }
}
