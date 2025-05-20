import SwiftUI

struct ConversationComposerView: UIViewControllerRepresentable {
    let draftConversationRepository: any ConversationRepositoryProtocol
    let messagesStore: MessagesStoreProtocol
    @State private var draftConversationState: DraftConversationState

    init(
        draftConversationRepository: any ConversationRepositoryProtocol,
        messagesStore: MessagesStoreProtocol
    ) {
        self.draftConversationRepository = draftConversationRepository
        self.messagesStore = messagesStore
        _draftConversationState = State(
            initialValue: .init(
                draftConversationRepository: draftConversationRepository
            )
        )
    }

    func makeUIViewController(context: Context) -> ConversationComposerViewController {
        let composerViewController = ConversationComposerViewController(
            messagesStore: messagesStore
        )
        return composerViewController
    }

    func updateUIViewController(_ composerViewController: ConversationComposerViewController, context: Context) {
        composerViewController.messagesViewController
            .set(title: "New chat", avatarImage: nil)
    }
}

#Preview {
    ConversationComposerView(
        draftConversationRepository: MockDraftConversationRepository(),
        messagesStore: MockMessagesStore()
    )
    .ignoresSafeArea()
}
