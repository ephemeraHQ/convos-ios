import Foundation

protocol ProfileSearchRepositoryProtocol {
    func search(using query: String) async throws -> [ProfileSearchResult]
}

struct ProfileSearchResult: Hashable, Identifiable {
    var id: String { profile.id }
    let profile: Profile
    let xmtpId: String

    static func mock() -> ProfileSearchResult {
        .init(
            profile: .mock(),
            xmtpId: "mock-xmtp-id-\(UUID().uuidString.prefix(10))"
        )
    }
}

class ProfileSearchRepository: ProfileSearchRepositoryProtocol {
    let apiClient: any ConvosAPIClientProtocol

    init(apiClient: any ConvosAPIClientProtocol) {
        self.apiClient = apiClient
    }

    func search(using query: String) async throws -> [ProfileSearchResult] {
        let profiles = try await apiClient.getProfiles(matching: query)
        return profiles.map { apiProfile in
                .init(profile: .init(
                    id: apiProfile.id,
                    name: apiProfile.name,
                    username: apiProfile.username,
                    avatar: apiProfile.avatar
                ),
                      xmtpId: apiProfile.xmtpId
                )
        }
    }
}
