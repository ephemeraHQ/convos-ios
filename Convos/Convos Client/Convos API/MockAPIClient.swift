import Foundation

class MockAPIClient: ConvosAPIClientProtocol {
    var xmtpClientProvider: (any XMTPClientProvider)?

    func setXMTPClientProvider(_ provider: (any XMTPClientProvider)?) {
    }

    func authenticate(xmtpInstallationId: String, xmtpId: String, xmtpSignature: String) async throws -> String {
        return "mock-jwt-token"
    }

    func getUser() async throws -> ConvosAPI.UserResponse {
        return ConvosAPI.UserResponse(
            id: "user_123",
            identities: [
                ConvosAPI.UserResponse.Identity(
                    id: "identity_1",
                    turnkeyAddress: "0xMOCKADDRESS1",
                    xmtpId: "mock-xmtp-id"
                )
            ]
        )
    }

    func createUser(_ requestBody: ConvosAPI.CreateUserRequest) async throws -> ConvosAPI.CreatedUserResponse {
        return ConvosAPI.CreatedUserResponse(
            id: "created_user_123",
            turnkeyUserId: requestBody.turnkeyUserId,
            device: ConvosAPI.CreatedUserResponse.Device(
                id: "device_1",
                os: requestBody.device.os,
                name: requestBody.device.name
            ),
            identity: ConvosAPI.CreatedUserResponse.Identity(
                id: "identity_1",
                turnkeyAddress: requestBody.identity.turnkeyAddress,
                xmtpId: requestBody.identity.xmtpId
            ),
            profile: ConvosAPI.CreatedUserResponse.Profile(
                id: "profile_1",
                name: requestBody.profile.name,
                username: requestBody.profile.username,
                description: requestBody.profile.description,
                avatar: requestBody.profile.avatar
            )
        )
    }

    func checkUsername(_ username: String) async throws -> ConvosAPI.UsernameCheckResponse {
        return ConvosAPI.UsernameCheckResponse(taken: username == "takenusername")
    }

    func getProfile(inboxId: String) async throws -> ConvosAPI.ProfileResponse {
        return ConvosAPI.ProfileResponse(
            id: inboxId,
            name: "Mock User",
            username: "mockuser",
            description: "This is a mock profile.",
            avatar: nil,
            xmtpId: "mock-xmtp-id",
            turnkeyAddress: "0xMOCKADDRESS1"
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
                turnkeyAddress: "0xMOCKADDRESS\(id)"
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
                turnkeyAddress: "0xMOCKADDRESSSEARCH1"
            )
        ]
    }
}
