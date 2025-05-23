import Combine
import Foundation

extension User {
    static func mock() -> User {
        .init(
            id: UUID().uuidString,
            inboxId: UUID().uuidString,
            identities: [],
            profile: .mock()
        )
    }
}

extension Profile {
    static func mock(name: String = "Andrew") -> Profile {
        .init(
            id: UUID().uuidString,
            name: name,
            username: name.lowercased(),
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
