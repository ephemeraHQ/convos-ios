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

extension ConversationMember {
    static func mock(name: String = "Andrew") -> ConversationMember {
        .init(
            profile: .mock(name: name),
            role: MemberRole.allCases.randomElement() ?? .member,
            isCurrentUser: false
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

    lazy var userPublisher: AnyPublisher<User?, Never> = {
        Just(currentUser).eraseToAnyPublisher()
    }()

    func getCurrentUser() async throws -> User? {
        currentUser
    }
}
