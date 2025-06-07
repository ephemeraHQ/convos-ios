import Combine
import Foundation
import GRDB

protocol ConversationsCountRepositoryProtocol {
    var conversationsCount: AnyPublisher<Int, Never> { get }
    func fetchCount() throws -> Int
}

class ConversationsCountRepository: ConversationsCountRepositoryProtocol {
    private let databaseReader: DatabaseReader
    private let consent: [Consent]

    lazy var conversationsCount: AnyPublisher<Int, Never> = {
        ValueObservation
            .tracking { [weak self] db in
                guard let self else { return 0 }
                return try db.composeConversationsCount(consent: consent)
            }
            .publisher(in: databaseReader)
            .replaceError(with: 0)
            .eraseToAnyPublisher()
    }()

    init(databaseReader: DatabaseReader, consent: [Consent] = .all) {
        self.databaseReader = databaseReader
        self.consent = consent
    }

    func fetchCount() throws -> Int {
        try databaseReader.read { [weak self] db in
            guard let self else { return 0 }
            return try db.composeConversationsCount(consent: consent)
        }
    }
}

fileprivate extension Database {
    func composeConversationsCount(consent: [Consent]) throws -> Int {
        try DBConversation
            .filter(consent.contains(DBConversation.Columns.consent))
            .fetchCount(self)
    }
}
