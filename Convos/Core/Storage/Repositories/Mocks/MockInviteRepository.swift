import Combine
import Foundation

class MockInviteRepository: InviteRepositoryProtocol {
    var invitePublisher: AnyPublisher<Invite?, Never> {
        Just(.mock()).eraseToAnyPublisher()
    }
}
