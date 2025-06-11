import SwiftUI

struct ConversationComposerView: UIViewControllerRepresentable {
    @State private var draftConversationComposer: any DraftConversationComposerProtocol
    @State private var conversationComposerState: ConversationComposerState
    @Environment(\.dismiss) var dismissAction: DismissAction

    init(
        messagingService: any MessagingServiceProtocol,
        draftConversationComposer: any DraftConversationComposerProtocol
    ) {
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
            profileSearchRepository: draftConversationComposer.profileSearchRepository,
            dismissAction: dismissAction
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
