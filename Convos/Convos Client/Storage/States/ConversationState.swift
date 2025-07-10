import Combine
import Foundation
import Observation

@Observable
final class ConversationState {
    var conversationId: String {
        conversationRepository.conversationId
    }

    private(set) var conversation: Conversation?
    private(set) var membersWithRoles: [ProfileWithRole] = []
    private let conversationRepository: ConversationRepositoryProtocol
    private var cancellables: Set<AnyCancellable> = .init()

    var conversationPublisher: AnyPublisher<Conversation?, Never> {
        conversationRepository.conversationPublisher
    }

    var conversationWithRolesPublisher: AnyPublisher<(Conversation, [ProfileWithRole])?, Never> {
        conversationRepository.conversationWithRolesPublisher
    }

    init(conversationRepository: ConversationRepositoryProtocol) {
        self.conversationRepository = conversationRepository
        do {
            self.conversation = try conversationRepository.fetchConversation()
            // Fetch initial members with roles for group conversations
            if let conv = conversation, conv.kind == .group {
                if let (_, members) = try conversationRepository.fetchConversationWithRoles() {
                    self.membersWithRoles = members
                }
            }
        } catch {
            Logger.error("Error fetching conversation: \(error)")
            self.conversation = nil
            self.membersWithRoles = []
        }
        observe()
    }

    private func observe() {
                // Observe conversation changes
        conversationRepository.conversationPublisher
            .receive(on: DispatchQueue.main)
            .compactMap { $0 }
            .sink { [weak self] conversation in
                guard let self else { return }
                self.conversation = conversation
            }
            .store(in: &cancellables)

        // Observe members with roles changes
        conversationRepository.conversationWithRolesPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] conversationWithRoles in
                guard let self else { return }
                if let (_, members) = conversationWithRoles {
                    self.membersWithRoles = members
                } else {
                    self.membersWithRoles = []
                }
            }
            .store(in: &cancellables)
    }
}
