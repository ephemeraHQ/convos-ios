import Combine
import Foundation

extension User {
    static func mock(displayName: String = "Andrew") -> User {
        let userId = UUID().uuidString
        let inboxId = UUID().uuidString
        return .init(
            id: userId,
            inboxId: inboxId,
            identities: [
                .init(id: UUID().uuidString,
                      userId: userId,
                      walletAddress: "0x\(UUID().uuidString.lowercased())",
                      xmtpId: inboxId)
            ],
            profile: .mock(name: displayName)
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
