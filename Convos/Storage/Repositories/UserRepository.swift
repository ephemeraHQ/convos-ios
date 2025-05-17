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
            try db.composeCurrentUser()
        }
    }

    func userPublisher() -> AnyPublisher<User?, Never> {
        ValueObservation
            .tracking { db in
                try db.composeCurrentUser()
            }
            .publisher(in: dbReader)
            .replaceError(with: nil)
            .eraseToAnyPublisher()
    }
}

fileprivate extension Database {
    func composeCurrentUser() throws -> User? {
        guard let session = try Session.fetchOne(self) else { return nil }

        guard let dbUser = try DBUser.fetchOne(self, key: session.currentUserId) else { return nil }
        guard let userProfile = try UserProfile
            .filter(Column("userId") == dbUser.id)
            .fetchOne(self) else { return nil }

        let identities = try Identity
            .filter(Column("userId") == dbUser.id)
            .fetchAll(self)

        let profile = Profile(from: userProfile)
        return User(id: dbUser.id, identities: identities, profile: profile)
    }
}
