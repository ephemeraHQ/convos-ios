import Combine
import Foundation
import GRDB

protocol UserRepositoryProtocol {
    func getCurrentUser() async throws -> User?
    func userPublisher() -> AnyPublisher<User?, Never>
}

final class UserRepository: UserRepositoryProtocol {
    private let dbReader: any DatabaseReader

    init(dbReader: any DatabaseReader) {
        self.dbReader = dbReader
    }

    func getCurrentUser() async throws -> User? {
        try await dbReader.read { db in
            try db.currentUser()
        }
    }

    func userPublisher() -> AnyPublisher<User?, Never> {
        ValueObservation
            .tracking { db in
                try db.currentUser()
            }
            .publisher(in: dbReader)
            .replaceError(with: nil)
            .eraseToAnyPublisher()
    }
}
