import Combine
import Foundation

public class MockInviteRepository: InviteRepositoryProtocol {
    public init() {}
    public var invitePublisher: AnyPublisher<Invite?, Never> {
        Just(.mock()).eraseToAnyPublisher()
    }
}
