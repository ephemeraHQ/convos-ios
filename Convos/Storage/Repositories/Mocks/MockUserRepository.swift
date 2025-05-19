import Combine
import Foundation

extension User {
    static func mock() -> User {
        .init(
            id: UUID().uuidString,
            identities: [],
            profile: .mock()
        )
    }
}

extension Profile {
    static func mock() -> Profile {
        .init(
            id: UUID().uuidString,
            name: "Andrew",
            username: "courter",
            avatar: nil
        )
    }
}

class MockUserRepository: UserRepositoryProtocol {
    let currentUser: User = .mock()

    func getCurrentUser() async throws -> User? {
        currentUser
    }

    func userPublisher() -> AnyPublisher<User?, Never> {
        Just(currentUser).eraseToAnyPublisher()
    }
}
