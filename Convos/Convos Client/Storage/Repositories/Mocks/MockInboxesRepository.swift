import Combine
import Foundation

class MockInboxesRepository: InboxesRepositoryProtocol {
    var inboxesPublisher: AnyPublisher<[Inbox], Never> {
        Just((try? allInboxes()) ?? []).eraseToAnyPublisher()
    }

    func allInboxes() throws -> [Inbox] {
        [
            .init(
                inboxId: UUID().uuidString,
                identities: [],
                profile: .mock(),
                type: .ephemeral,
                provider: .local,
                providerId: UUID().uuidString
            )
        ]
    }
}

extension Profile {
    static func mock(name: String = "Andrew") -> Profile {
        .init(
            id: UUID().uuidString,
            name: name,
            username: name.lowercased(),
            avatar: nil
        )
    }
}
