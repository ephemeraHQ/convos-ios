import Combine
import Foundation
import Observation

@Observable
final class ConversationsListViewModel {
    private(set) var conversations: [Conversation]
    private(set) var securityLineConversationsCount: Int

    var selectedInbox: Inbox?

    var pinnedConversations: [Conversation] {
        conversations.filter { $0.isPinned }
    }
    var unpinnedConversations: [Conversation] {
        conversations.filter { !$0.isPinned }
    }

    private let conversationsRepository: any ConversationsRepositoryProtocol
    private let securityLineConversationsCountRepo: any ConversationsCountRepositoryProtocol
    private var cancellables: Set<AnyCancellable> = .init()

    init(conversationsRepository: any ConversationsRepositoryProtocol,
         securityLineConversationsCountRepo: any ConversationsCountRepositoryProtocol) {
        self.conversationsRepository = conversationsRepository
        self.securityLineConversationsCountRepo = securityLineConversationsCountRepo
        do {
            self.conversations = try conversationsRepository.fetchAll()
        } catch {
            Logger.error("Error fetching conversations: \(error)")
            self.conversations = []
        }
        do {
            self.securityLineConversationsCount = try securityLineConversationsCountRepo.fetchCount()
        } catch {
            Logger.error("Error fetching security line conversations: \(error)")
            self.securityLineConversationsCount = 0
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
        securityLineConversationsCountRepo.conversationsCount
            .receive(on: DispatchQueue.main)
            .sink { [weak self] count in
                self?.securityLineConversationsCount = count
            }
            .store(in: &cancellables)
    }
}
