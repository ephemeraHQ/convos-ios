import Combine
import Foundation
import Observation

@Observable
final class ConversationState {
    var conversationId: String {
        conversationRepository.conversationId
    }

    private(set) var conversation: Conversation?
    private let conversationRepository: ConversationRepositoryProtocol
    private var cancellables: Set<AnyCancellable> = .init()

    init(conversationRepository: ConversationRepositoryProtocol) {
        self.conversationRepository = conversationRepository
        do {
            self.conversation = try conversationRepository.fetchConversation()
        } catch {
            Logger.error("Error fetching conversation: \(error)")
            self.conversation = nil
        }
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
