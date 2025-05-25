import SwiftUI

struct ConversationComposerView: UIViewControllerRepresentable {
    let draftConversationComposer: any DraftConversationComposerProtocol
    @State private var draftConversationState: DraftConversationState

    init(
        draftConversationComposer: any DraftConversationComposerProtocol
    ) {
        self.draftConversationComposer = draftConversationComposer
        _draftConversationState = State(
            initialValue: .init(
                draftConversationRepository:
                    draftConversationComposer.draftConversationRepository
            )
        )
    }

    func makeUIViewController(context: Context) -> ConversationComposerViewController {
        let composerViewController = ConversationComposerViewController(
            messagesRepository: draftConversationComposer.messagesRepository,
            outgoingMessageWriter: draftConversationComposer.outgoingMessageWriter,
            profileSearchRepository: draftConversationComposer.profileSearchRepository
        )
        return composerViewController
    }

    func updateUIViewController(_ composerViewController: ConversationComposerViewController, context: Context) {
        composerViewController.messagesViewController
            .navigationBar.configure(
                conversation: nil,
                placeholderTitle: "New chat"
            )
    }
}

#Preview {
    ConversationComposerView(
        draftConversationComposer: MockDraftConversationComposer()
    )
    .ignoresSafeArea()
}
