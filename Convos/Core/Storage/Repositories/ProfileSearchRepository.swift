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
    private let inboxReadyPublisher: InboxReadyResultPublisher
    private let inboxReadyValue: PublisherValue<InboxReadyResult>

    init(
        inboxReady: InboxReadyResult?,
        inboxReadyPublisher: InboxReadyResultPublisher
    ) {
        self.inboxReadyPublisher = inboxReadyPublisher
        self.inboxReadyValue = .init(initial: inboxReady, upstream: inboxReadyPublisher)
    }

    deinit {
        cleanup()
    }

    func cleanup() {
        inboxReadyValue.dispose()
    }

    func search(using query: String) async throws -> [ProfileSearchResult] {
        guard let result = inboxReadyValue.value else {
            throw InboxStateError.inboxNotReady
        }

        if query.isValidEthereumAddressFormat {
            guard let inboxId = try await result.client.inboxId(for: query) else {
                return []
            }
            guard let profile = try? await result.apiClient.getProfile(inboxId: inboxId) else {
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
            let profiles = try await result.apiClient.getProfiles(matching: query)
            return profiles.map { $0.profileSearchResult }
        }
    }
}
