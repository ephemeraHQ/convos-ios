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
    private(set) var promptToKeepConversation: Bool = true // false once

    private var addAccountResult: AddAccountResultType?
    private var newConversationTask: Task<Void, Never>?

    init(session: any SessionManagerProtocol) {
        self.session = session
        newConversation()
    }

    private func newConversation() {
        newConversationTask = Task {
            do {
                let addAccountResult = try session.addAccount()
                self.addAccountResult = addAccountResult
                let draftConversationComposer = addAccountResult.messagingService.draftConversationComposer()
                self.draftConversationComposer = draftConversationComposer
                self.conversationState = ConversationState(
                    myProfileRepository: addAccountResult.messagingService.myProfileRepository(),
                    conversationRepository: draftConversationComposer.draftConversationRepository
                )
            } catch {
                Logger.error("Error starting new conversation: \(error.localizedDescription)")
            }
        }
    }

    func deleteConversation() throws {
        newConversationTask?.cancel()
        guard let addAccountResult else { return }
        try session.deleteAccount(with: addAccountResult.providerId)
        self.addAccountResult = nil
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
            promptToKeepConversation = false
        }
        .store(in: &cancellables)
    }
}
