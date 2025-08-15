import Combine
import Foundation

public class MockInboxesService: SessionManagerProtocol {
    public init() {
    }

    public var authState: AnyPublisher<AuthServiceState, Never> {
        Just(AuthServiceState.unknown).eraseToAnyPublisher()
    }

    public func prepare() throws {
    }

    public func addAccount() throws -> AddAccountResultType {
        .init(providerId: "", messagingService: MockMessagingService())
    }

    public func deleteAccount(inboxId: String) throws {
    }

    public func deleteAccount(providerId: String) throws {
    }

    public func deleteAllAccounts() throws {
    }

    public var inboxesRepository: any InboxesRepositoryProtocol {
        self
    }

    public func messagingService(for inboxId: String) -> AnyMessagingService {
        MockMessagingService()
    }

    public func conversationsRepository(for consent: [Consent]) -> any ConversationsRepositoryProtocol {
        MockConversationsRepository()
    }

    public func conversationsCountRepo(for consent: [Consent], kinds: [ConversationKind]) -> any ConversationsCountRepositoryProtocol {
        self
    }
}

extension MockInboxesService: ConversationsCountRepositoryProtocol {
    public var conversationsCount: AnyPublisher<Int, Never> {
        Just(1).eraseToAnyPublisher()
    }

    public func fetchCount() throws -> Int {
        1
    }
}

extension MockInboxesService: InboxesRepositoryProtocol {
    public var inboxesPublisher: AnyPublisher<[Inbox], Never> {
        Just((try? allInboxes()) ?? [])
            .eraseToAnyPublisher()
    }

    public func allInboxes() throws -> [Inbox] {
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
