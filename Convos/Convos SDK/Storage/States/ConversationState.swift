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
        self.conversation = .draft()
        observe()
    }

    private func observe() {
        conversationRepository.conversationPublisher()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] conversation in
                guard let self else { return }
                // TODO: we should really never not have a conversation here,
                // but figure out a better way to handle this
                self.conversation = conversation ?? .draft()
            }
            .store(in: &cancellables)
    }
}
