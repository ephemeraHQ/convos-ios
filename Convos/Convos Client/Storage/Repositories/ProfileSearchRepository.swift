import Foundation

protocol ProfileSearchRepositoryProtocol {
    func search(using query: String) async throws -> [Profile]
}

class ProfileSearchRepository: ProfileSearchRepositoryProtocol {
    let apiClient: any ConvosAPIClientProtocol

    init(apiClient: any ConvosAPIClientProtocol) {
        self.apiClient = apiClient
    }

    func search(using query: String) async throws -> [Profile] {
        let profiles = try await apiClient.getProfiles(matching: query)
        return profiles.map { apiProfile in
                .init(id: apiProfile.id,
                      name: apiProfile.name,
                      username: apiProfile.username,
                      avatar: apiProfile.avatar)
        }
    }
}
