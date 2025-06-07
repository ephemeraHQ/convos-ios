import Combine
import Foundation
import Observation

@Observable
final class ConversationsState {
    private(set) var conversations: [Conversation]

    private let conversationsRepository: any ConversationsRepositoryProtocol
    private var cancellables: Set<AnyCancellable> = .init()

    init(conversationsRepository: any ConversationsRepositoryProtocol) {
        self.conversationsRepository = conversationsRepository
        do {
            self.conversations = try conversationsRepository.fetchAll()
        } catch {
            Logger.error("Error fetching conversations: \(error)")
            self.conversations = []
        }
        observe()
    }

    private func observe() {
        conversationsRepository.conversationsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] conversations in
                self?.conversations = conversations
            }
            .store(in: &cancellables)
    }
}
