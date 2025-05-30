import Combine
import Foundation
import Observation

@Observable
final class ConversationState {
    var conversation: Conversation

    private let conversationRepository: ConversationRepositoryProtocol
    private var cancellables: Set<AnyCancellable> = .init()

    init(conversationRepository: ConversationRepositoryProtocol) {
        self.conversationRepository = conversationRepository
        self.conversation = .mock()
        observe()
    }

    private func observe() {
        conversationRepository.conversationPublisher
            .receive(on: DispatchQueue.main)
            .compactMap { $0 }
            .sink { [weak self] conversation in
                guard let self else { return }
                self.conversation = conversation
            }
            .store(in: &cancellables)
    }
}
