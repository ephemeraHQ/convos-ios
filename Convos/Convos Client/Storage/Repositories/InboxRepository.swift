import Combine
import Foundation
import GRDB

protocol InboxRepositoryProtocol {
    var inboxPublisher: AnyPublisher<Inbox, Never> { get }

    func fetchInbox() throws -> Inbox
}

final class InboxRepository: InboxRepositoryProtocol {
    private let databaseReader: any DatabaseReader

    var inboxPublisher: AnyPublisher<Inbox, Never> {
        Just(.init(inboxId: "", identities: [], profile: .mock()))
            .eraseToAnyPublisher()
    }

    init(databaseReader: any DatabaseReader) {
        self.databaseReader = databaseReader
    }

    func fetchInbox() throws -> Inbox {
        .init(inboxId: "", identities: [], profile: .mock())
    }
}
