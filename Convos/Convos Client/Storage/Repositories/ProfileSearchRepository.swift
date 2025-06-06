import Combine
import Foundation

protocol ProfileSearchRepositoryProtocol {
    func search(using query: String) async throws -> [ProfileSearchResult]
}

struct ProfileSearchResult: Hashable, Identifiable {
    var id: String { profile.id }
    let profile: Profile
    let inboxId: String

    static func mock() -> ProfileSearchResult {
        .init(
            profile: .mock(),
            inboxId: "mock-xmtp-id-\(UUID().uuidString.prefix(10))"
        )
    }
}

extension ConvosAPI.ProfileResponse {
    var profileSearchResult: ProfileSearchResult {
        .init(
            profile: .init(
                id: xmtpId,
                name: name, username: username, avatar: avatar
            ),
            inboxId: xmtpId
        )
    }
}

class ProfileSearchRepository: ProfileSearchRepositoryProtocol {
    private let apiClient: any ConvosAPIClientProtocol
    private let clientPublisher: AnyPublisher<(any XMTPClientProvider)?, Never>
    private var clientProvider: (any XMTPClientProvider)?
    private var cancellable: AnyCancellable?

    init(apiClient: any ConvosAPIClientProtocol,
         clientPublisher: AnyPublisher<(any XMTPClientProvider)?, Never>) {
        self.apiClient = apiClient
        self.clientPublisher = clientPublisher
        cancellable = clientPublisher.sink { [weak self] clientProvider in
            guard let self else { return }
            self.clientProvider = clientProvider
        }
    }

    func search(using query: String) async throws -> [ProfileSearchResult] {
        if query.isValidEthereumAddressFormat {
            guard let clientProvider else {
                Logger.error("Attempting profile search from wallet address without XMTP Client Provider")
                return []
            }
            guard let inboxId = try await clientProvider.inboxId(for: query) else {
                return []
            }
            guard let profile = try? await apiClient.getProfile(inboxId: inboxId) else {
                return [
                    .init(
                        profile: .init(
                            id: inboxId,
                            name: inboxId,
                            username: inboxId,
                            avatar: nil
                        ), inboxId: inboxId
                    )
                ]
            }
            return [profile.profileSearchResult]
        } else {
            let profiles = try await apiClient.getProfiles(matching: query)
            return profiles.map { $0.profileSearchResult }
        }
    }
}
