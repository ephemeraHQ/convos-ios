import Combine
import OrderedCollections
import SwiftUI

@Observable
class NewConversationState {
    private var cancellables: Set<AnyCancellable> = []
    private let session: any SessionManagerProtocol
    private(set) var conversationState: ConversationState?
    private(set) var draftConversationComposer: (any DraftConversationComposerProtocol)? {
        didSet {
            setupObservations()
        }
    }
    private(set) var showJoinConversation: Bool = true // false once someone joins or a message is sent

    init(session: any SessionManagerProtocol) {
        self.session = session
        newConversation()
    }

    private func newConversation() {
        Task {
            do {
                let messagingService = try session.addAccount()
                let draftConversationComposer = messagingService.draftConversationComposer()
                self.draftConversationComposer = draftConversationComposer
                self.conversationState = ConversationState(
                    myProfileRepository: messagingService.myProfileRepository(),
                    conversationRepository: draftConversationComposer.draftConversationRepository
                )
            } catch {
                Logger.error("Error starting new conversation: \(error.localizedDescription)")
            }
        }
    }

    private func setupObservations() {
        cancellables.removeAll()

        guard let draftConversationComposer else {
            return
        }

        Publishers.Merge(
            draftConversationComposer.draftConversationWriter.sentMessage.map { _ in () },
            draftConversationComposer.draftConversationRepository.membersPublisher
                .filter { !$0.isEmpty }
                .dropFirst()
                .map { _ in () }
        )
        .eraseToAnyPublisher()
        .receive(on: DispatchQueue.main)
        .sink { [weak self] in
            guard let self else { return }
            showJoinConversation = false
        }
        .store(in: &cancellables)
    }
}
