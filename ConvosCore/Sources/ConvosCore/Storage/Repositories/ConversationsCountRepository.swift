import Combine
import Foundation
import GRDB

public protocol ConversationsCountRepositoryProtocol {
    var conversationsCount: AnyPublisher<Int, Never> { get }
    func fetchCount() throws -> Int
}

class ConversationsCountRepository: ConversationsCountRepositoryProtocol {
    private let databaseReader: DatabaseReader
    private let consent: [Consent]
    private let kinds: [ConversationKind]

    lazy var conversationsCount: AnyPublisher<Int, Never> = {
        ValueObservation
            .tracking { [weak self] db in
                guard let self else { return 0 }
                return try db.composeConversationsCount(consent: consent, kinds: kinds)
            }
            .publisher(in: databaseReader)
            .replaceError(with: 0)
            .eraseToAnyPublisher()
    }()

    init(databaseReader: DatabaseReader, consent: [Consent] = .all, kinds: [ConversationKind] = .all) {
        self.databaseReader = databaseReader
        self.consent = consent
        self.kinds = kinds
    }

    func fetchCount() throws -> Int {
        try databaseReader.read { [weak self] db in
            guard let self else { return 0 }
            return try db.composeConversationsCount(consent: consent, kinds: kinds)
        }
    }
}

fileprivate extension Database {
    func composeConversationsCount(consent: [Consent], kinds: [ConversationKind]) throws -> Int {
        try DBConversation
            .filter(!Column("id").like("draft-%"))
            .filter(kinds.contains(DBConversation.Columns.kind))
            .filter(consent.contains(DBConversation.Columns.consent))
            .fetchCount(self)
    }
}
