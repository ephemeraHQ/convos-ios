import Combine
import Foundation

class MockInboxesService: SessionManagerProtocol {
    var authState: AnyPublisher<AuthServiceState, Never> {
        Just(AuthServiceState.unknown).eraseToAnyPublisher()
    }

    func prepare() async throws {
    }

    var inboxesRepository: any InboxesRepositoryProtocol {
        self
    }

    func messagingService(for inboxId: String) -> AnyMessagingService {
        MockMessagingService()
    }

    func conversationsRepository(for consent: [Consent]) -> any ConversationsRepositoryProtocol {
        MockConversationsRepository()
    }

    func conversationsCountRepo(for consent: [Consent]) -> any ConversationsCountRepositoryProtocol {
        self
    }
}

extension MockInboxesService: ConversationsCountRepositoryProtocol {
    var conversationsCount: AnyPublisher<Int, Never> {
        Just(1).eraseToAnyPublisher()
    }

    func fetchCount() throws -> Int {
        1
    }
}

extension MockInboxesService: InboxesRepositoryProtocol {
    var inboxesPublisher: AnyPublisher<[Inbox], Never> {
        Just((try? allInboxes()) ?? [])
            .eraseToAnyPublisher()
    }

    func allInboxes() throws -> [Inbox] {
        [
            Inbox(
                inboxId: "1",
                identities: [],
                profile: .mock(),
                type: .ephemeral,
                provider: .local,
                providerId: UUID().uuidString
            )
        ]
    }
}
