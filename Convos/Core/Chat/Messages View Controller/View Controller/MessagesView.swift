import SwiftUI

struct MessagesView: UIViewControllerRepresentable {
    let conversationRepository: any ConversationRepositoryProtocol
    let messagesRepository: any MessagesRepositoryProtocol
    @State private var conversationState: ConversationState

    init(conversationRepository: ConversationRepositoryProtocol,
         messagesRepository: any MessagesRepositoryProtocol) {
        self.conversationRepository = conversationRepository
        self.messagesRepository = messagesRepository
        _conversationState = State(
            initialValue: .init(
                conversationRepository: conversationRepository
            )
        )
    }

    func makeUIViewController(context: Context) -> MessagesViewController {
        let messageViewController = MessagesViewController(messagesRepository: messagesRepository)
        return messageViewController
    }

    func updateUIViewController(_ uiViewController: MessagesViewController, context: Context) {
    }
}

#Preview {
    MessagesView(conversationRepository: MockConversationRepository(),
                 messagesRepository: MockMessagesRepository())
        .ignoresSafeArea()
}
