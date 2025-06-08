import SwiftUI

struct ConversationComposerView: UIViewControllerRepresentable {
    let messagingService: any MessagingServiceProtocol
    let draftConversationComposer: any DraftConversationComposerProtocol
    @State private var conversationComposerState: ConversationComposerState

    init(
        messagingService: any MessagingServiceProtocol,
        draftConversationComposer: any DraftConversationComposerProtocol
    ) {
        self.messagingService = messagingService
        self.draftConversationComposer = draftConversationComposer
        _conversationComposerState = State(
            initialValue: .init(
                profileSearchRepository: draftConversationComposer.profileSearchRepository,
                draftConversationRepo: draftConversationComposer.draftConversationRepository,
                draftConversationWriter: draftConversationComposer.draftConversationWriter,
                conversationConsentWriter: draftConversationComposer.conversationConsentWriter,
                conversationLocalStateWriter: draftConversationComposer.conversationLocalStateWriter,
                messagesRepository: draftConversationComposer.draftConversationRepository.messagesRepository
            )
        )
    }

    func makeUIViewController(context: Context) -> ConversationComposerViewController {
        let composerViewController = ConversationComposerViewController(
            composerState: conversationComposerState,
            profileSearchRepository: draftConversationComposer.profileSearchRepository
        )
        return composerViewController
    }

    func updateUIViewController(_ composerViewController: ConversationComposerViewController, context: Context) {
    }
}

#Preview {
    ConversationComposerView(
        messagingService: MockMessagingService(),
        draftConversationComposer: MockDraftConversationComposer()
    )
    .ignoresSafeArea()
}
