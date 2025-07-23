import Combine
import Foundation
import Observation

@Observable
final class ConversationState {
    var conversationId: String {
        conversationRepository.conversationId
    }

    private(set) var myProfile: Profile = .empty()
    private(set) var conversation: Conversation
    private let myProfileRepository: any MyProfileRepositoryProtocol
    private let conversationRepository: any ConversationRepositoryProtocol
    private var cancellables: Set<AnyCancellable> = .init()

    var conversationPublisher: AnyPublisher<Conversation?, Never> {
        conversationRepository.conversationPublisher
    }

    init(
        myProfileRepository: any MyProfileRepositoryProtocol,
        conversationRepository: any ConversationRepositoryProtocol
    ) {
        self.myProfileRepository = myProfileRepository
        self.conversationRepository = conversationRepository
        self.conversation = .empty(id: conversationRepository.conversationId)
        do {
            self.conversation = try conversationRepository.fetchConversation() ?? .empty(id: conversationId)
        } catch {
            Logger.error("Error fetching conversation: \(error)")
        }
        observe()
    }

    private func observe() {
        myProfileRepository.myProfilePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] myProfile in
                guard let self else { return }
                self.myProfile = myProfile
            }
            .store(in: &cancellables)
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
