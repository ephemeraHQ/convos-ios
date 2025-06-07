import Combine
import Foundation
import Observation

@Observable
final class ConversationsState {
    private var conversations: [Conversation]

    private var allowedConversation: [Conversation] {
        conversations.filter { $0.consent == .allowed }
    }

    var securityLineConversations: [Conversation] {
        conversations.filter { $0.consent == .unknown }
    }

    var deniedConversations: [Conversation] {
        conversations.filter { $0.consent == .denied }
    }

    var pinnedConversations: [Conversation] {
        allowedConversation.filter { $0.isPinned }
    }
    var unpinnedConversations: [Conversation] {
        allowedConversation.filter { !$0.isPinned }
    }

    private let conversationsRepository: ConversationsRepositoryProtocol
    private var cancellables: Set<AnyCancellable> = .init()

    init(conversationsRepository: ConversationsRepositoryProtocol) {
        print("initializing conversations state")
        self.conversationsRepository = conversationsRepository
        do {
            self.conversations = try conversationsRepository.fetchAll()
        } catch {
            Logger.error("Error fetching conversations in: \(error)")
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
