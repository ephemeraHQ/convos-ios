import Combine
import Foundation
import GRDB

public protocol InboxesRepositoryProtocol {
    var inboxesPublisher: AnyPublisher<[Inbox], Never> { get }

    func allInboxes() throws -> [Inbox]
}

final class InboxesRepository: InboxesRepositoryProtocol {
    private let databaseReader: any DatabaseReader

    let inboxesPublisher: AnyPublisher<[Inbox], Never>

    init(databaseReader: any DatabaseReader) {
        self.databaseReader = databaseReader
        self.inboxesPublisher = ValueObservation
            .tracking { db in
                try db.composeAllInboxes()
            }
            .publisher(in: databaseReader)
            .replaceError(with: [])
            .eraseToAnyPublisher()
    }

    func allInboxes() throws -> [Inbox] {
        try databaseReader.read { db in
            try db.composeAllInboxes()
        }
    }
}

extension Array where Element == DBInboxDetails {
    func composeInboxes(from database: Database) throws -> [Inbox] {
        map { dbInbox in
            dbInbox.hydrateInbox()
        }
    }
}

fileprivate extension Database {
    func composeAllInboxes() throws -> [Inbox] {
        let dbInboxDetails = try DBInbox
            .including(all: DBInbox.identities)
            .including(required: DBInbox.memberProfile)
            .asRequest(of: DBInboxDetails.self)
            .fetchAll(self)

        return try dbInboxDetails.composeInboxes(from: self)
    }
}
