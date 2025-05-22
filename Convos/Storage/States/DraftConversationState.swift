import Combine
import Foundation
import Observation

extension Conversation {
    static func draft() -> Self {
        .init(
            id: Conversation.draftPrimaryKey,
            creator: .empty,
            createdAt: .distantFuture,
            kind: .dm,
            topic: "",
            members: [],
            otherMember: nil,
            messages: [],
            isPinned: false,
            isUnread: false,
            isMuted: false,
            lastMessage: nil,
            imageURL: nil
        )
    }

    var isDraft: Bool {
        id == Conversation.draftPrimaryKey
    }
}

@Observable
final class DraftConversationState {
    var draftConversation: Conversation?

    private let draftConversationRepository: any ConversationRepositoryProtocol
    private var cancellables: Set<AnyCancellable> = .init()

    init(draftConversationRepository: any ConversationRepositoryProtocol) {
        self.draftConversationRepository = draftConversationRepository
        observe()
    }

    private func observe() {
        draftConversationRepository.conversationPublisher()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] conversation in
                guard let self else { return }
                self.draftConversation = conversation
            }
            .store(in: &cancellables)
    }
}
