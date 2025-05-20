import SwiftUI

struct MessagesView: UIViewControllerRepresentable {
    let conversationRepository: any ConversationRepositoryProtocol
    let messagesStore: any MessagesStoreProtocol
    @State private var conversationState: ConversationState

    init(conversationRepository: ConversationRepositoryProtocol,
         messagesStore: MessagesStoreProtocol) {
        self.conversationRepository = conversationRepository
        self.messagesStore = messagesStore
        _conversationState = State(
            initialValue: .init(
                conversationRepository: conversationRepository
            )
        )
    }

    func makeUIViewController(context: Context) -> MessagesViewController {
        let messageViewController = MessagesViewController(messagesStore: messagesStore)
        return messageViewController
    }

    func updateUIViewController(_ uiViewController: MessagesViewController, context: Context) {
    }
}

#Preview {
    MessagesView(conversationRepository: MockConversationRepository(),
                 messagesStore: MockMessagesStore())
        .ignoresSafeArea()
}
