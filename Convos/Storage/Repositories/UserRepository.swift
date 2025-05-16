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
            guard let session = try Session.fetchOne(db) else { return nil }

            // Fetch base user row (has id)
            guard let dbUser = try DBUser.fetchOne(db, key: session.currentUserId) else { return nil }

            // Fetch profile and identities
            guard let profile = try Profile
                .filter(Column("userId") == dbUser.id)
                .fetchOne(db) else { return nil }

            let identities = try Identity
                .filter(Column("userId") == dbUser.id)
                .fetchAll(db)

            // Compose and return
            return User(id: dbUser.id, identities: identities, profile: profile)
        }
    }

    func userPublisher() -> AnyPublisher<User?, Never> {
        ValueObservation
            .tracking { db in
                guard let session = try Session.fetchOne(db) else { return nil }

                guard let dbUser = try DBUser.fetchOne(db, key: session.currentUserId) else { return nil }
                guard let profile = try Profile
                    .filter(Column("userId") == dbUser.id)
                    .fetchOne(db) else { return nil }

                let identities = try Identity
                    .filter(Column("userId") == dbUser.id)
                    .fetchAll(db)

                return User(id: dbUser.id, identities: identities, profile: profile)
            }
            .publisher(in: dbReader)
            .replaceError(with: nil)
            .eraseToAnyPublisher()
    }
}
