import Combine
import Foundation
import GRDB

protocol CurrentSessionRepositoryProtocol {
    var currentSessionPublisher: AnyPublisher<CurrentSession?, Never> { get }

    func getCurrentSession() async throws -> CurrentSession?
}

final class CurrentSessionRepository: CurrentSessionRepositoryProtocol {
    private let dbReader: any DatabaseReader

    lazy var currentSessionPublisher: AnyPublisher<CurrentSession?, Never> = {
        ValueObservation
            .tracking { db in
                try db.currentSession()
            }
            .publisher(in: dbReader)
            .replaceError(with: nil)
            .eraseToAnyPublisher()
    }()

    init(dbReader: any DatabaseReader) {
        self.dbReader = dbReader
    }

    func getCurrentSession() async throws -> CurrentSession? {
        try await dbReader.read { db in
            try db.currentSession()
        }
    }
}
