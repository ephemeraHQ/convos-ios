import Combine
import SwiftUI

@Observable
final class ConversationsViewModel {
    let convos: ConvosSDK.Convos
    private var cancellables: Set<AnyCancellable> = .init()
    private(set) var messagingState: ConvosSDK.MessagingServiceState = .uninitialized

    init(convos: ConvosSDK.Convos) {
        self.convos = convos
        observeMessagingState()
    }

    // MARK: - Public

    func signOut() {
        Task {
            do {
                try await convos.signOut()
            } catch {
                Logger.error("Error signing out: \(error)")
            }
        }
    }

    // MARK: - Private

    private func observeMessagingState() {
        convos.messaging.messagingStatePublisher()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.messagingState = state
            }
            .store(in: &cancellables)
    }
}
