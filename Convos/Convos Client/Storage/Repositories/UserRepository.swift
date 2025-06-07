import Combine
import Foundation
import GRDB

protocol UserRepositoryProtocol {
    var userPublisher: AnyPublisher<User?, Never> { get }

    func getCurrentUser() async throws -> User?
}

final class UserRepository: UserRepositoryProtocol {
    private let dbReader: any DatabaseReader

    lazy var userPublisher: AnyPublisher<User?, Never> = {
        ValueObservation
            .tracking { db in
                try db.currentUser()
            }
            .publisher(in: dbReader)
            .replaceError(with: nil)
            .eraseToAnyPublisher()
    }()

    init(dbReader: any DatabaseReader) {
        self.dbReader = dbReader
    }

    func getCurrentUser() async throws -> User? {
        try await dbReader.read { db in
            try db.currentUser()
        }
    }
}
