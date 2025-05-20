import SwiftUI

struct ConversationComposerView: UIViewControllerRepresentable {
    let draftConversationRepository: any ConversationRepositoryProtocol
    let messagingService: any ConvosSDK.MessagingServiceProtocol
    let messagesStore: MessagesStoreProtocol
    @State private var draftConversationState: DraftConversationState

    init(
        draftConversationRepository: any ConversationRepositoryProtocol,
        messagingService: any ConvosSDK.MessagingServiceProtocol,
        messagesStore: MessagesStoreProtocol
    ) {
        self.draftConversationRepository = draftConversationRepository
        self.messagingService = messagingService
        self.messagesStore = messagesStore
        _draftConversationState = State(
            initialValue: .init(
                draftConversationRepository: draftConversationRepository
            )
        )
    }

    func makeUIViewController(context: Context) -> ConversationComposerViewController {
        let composerViewController = ConversationComposerViewController(
            messagesStore: messagesStore,
            messagingService: messagingService
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
        messagingService: MockMessagingService(),
        messagesStore: MockMessagesStore()
    )
    .ignoresSafeArea()
}
