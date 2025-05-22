import SwiftUI

struct ConversationComposerView: UIViewControllerRepresentable {
    let draftConversationRepository: any ConversationRepositoryProtocol
    let messagingService: any ConvosSDK.MessagingServiceProtocol
    let messagesRepository: any MessagesRepositoryProtocol
    @State private var draftConversationState: DraftConversationState

    init(
        draftConversationRepository: any ConversationRepositoryProtocol,
        messagingService: any ConvosSDK.MessagingServiceProtocol,
        messagesRepository: any MessagesRepositoryProtocol
    ) {
        self.draftConversationRepository = draftConversationRepository
        self.messagingService = messagingService
        self.messagesRepository = messagesRepository
        _draftConversationState = State(
            initialValue: .init(
                draftConversationRepository: draftConversationRepository
            )
        )
    }

    func makeUIViewController(context: Context) -> ConversationComposerViewController {
        let composerViewController = ConversationComposerViewController(
            messagesRepository: messagesRepository,
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
        messagesRepository: MockMessagesRepository()
    )
    .ignoresSafeArea()
}
