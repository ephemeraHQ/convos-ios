import Combine
import Foundation

public class MockInboxesService: SessionManagerProtocol {
    public func shouldDisplayNotification(for conversationId: String) async -> Bool {
        true
    }

    public init() {
    }

    public var authState: AnyPublisher<AuthServiceState, Never> {
        Just(AuthServiceState.unknown).eraseToAnyPublisher()
    }

    public func addInbox() async throws -> AnyMessagingService {
        MockMessagingService()
    }

    public func deleteInbox(inboxId: String) async throws {
    }

    public func deleteAllInboxes() async throws {
    }

    public func deleteInbox(for messagingService: AnyMessagingService) async throws {
    }

    public func deleteAllAccounts() throws {
    }

    public var inboxesRepository: any InboxesRepositoryProtocol {
        self
    }

    public func messagingService(for inboxId: String) async -> AnyMessagingService {
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
                profile: .mock()
            )
        ]
    }
}
