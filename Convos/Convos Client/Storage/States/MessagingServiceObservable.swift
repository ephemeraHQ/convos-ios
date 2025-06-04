import Combine
import Foundation
import Observation

@Observable
class MessagingServiceObservable {
    let messagingService: any MessagingServiceProtocol
    private var cancellables: Set<AnyCancellable> = .init()

    private var state: MessagingServiceState
    private(set) var canStartConversation: Bool

    init(messagingService: any MessagingServiceProtocol) {
        self.messagingService = messagingService
        self.state = messagingService.state
        self.canStartConversation = messagingService.state.isReady
        observe()
    }

    private func observe() {
        messagingService.messagingStatePublisher
            .receive(on: DispatchQueue.main)
            .sink(receiveValue: { state in
                print("State changed: \(state)")
                self.state = state
            })
            .store(in: &cancellables)
    }
}
