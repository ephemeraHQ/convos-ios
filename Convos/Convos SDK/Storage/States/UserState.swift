import Combine
import Foundation
import Observation

@Observable
final class UserState {
    var currentUser: User?

    private let userRepository: UserRepositoryProtocol
    private var cancellables: Set<AnyCancellable> = .init()

    init(userRepository: UserRepositoryProtocol) {
        self.userRepository = userRepository
        observe()
    }

    private func observe() {
        userRepository.userPublisher()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] user in
                self?.currentUser = user
            }
            .store(in: &cancellables)
    }

    func reload() async {
        do {
            currentUser = try await userRepository.getCurrentUser()
        } catch {
            Logger.error("Failed to load user: \(error)")
        }
    }
}
