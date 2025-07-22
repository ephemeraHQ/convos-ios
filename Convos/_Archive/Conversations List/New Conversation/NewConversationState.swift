import Combine
import OrderedCollections
import SwiftUI

@Observable
class NewConversationState {
    private var cancellables: Set<AnyCancellable> = []
    private let session: any SessionManagerProtocol
    private(set) var conversationState: ConversationState?
    private(set) var draftConversationComposer: (any DraftConversationComposerProtocol)?

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
                    conversationRepository: draftConversationComposer.draftConversationRepository
                )
            } catch {
                Logger.error("Error starting new conversation: \(error.localizedDescription)")
            }
        }
    }
}
