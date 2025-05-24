import SwiftUI

struct MessagesView: UIViewControllerRepresentable {
    let conversationRepository: any ConversationRepositoryProtocol
    let messageWriter: any OutgoingMessageWriterProtocol
    let messagesRepository: any MessagesRepositoryProtocol
    @State private var conversationState: ConversationState

    init(conversationRepository: ConversationRepositoryProtocol,
         messageWriter: any OutgoingMessageWriterProtocol,
         messagesRepository: any MessagesRepositoryProtocol) {
        self.conversationRepository = conversationRepository
        self.messageWriter = messageWriter
        self.messagesRepository = messagesRepository
        _conversationState = State(
            initialValue: .init(
                conversationRepository: conversationRepository
            )
        )
    }

    func makeUIViewController(context: Context) -> MessagesViewController {
        let messageViewController = MessagesViewController(
            messageWriter: messageWriter,
            messagesRepository: messagesRepository)
        return messageViewController
    }

    func updateUIViewController(_ uiViewController: MessagesViewController, context: Context) {
    }
}

#Preview {
    let convos = ConvosClient.mock()
    let conversationId: String = "1"
    MessagesView(
        conversationRepository: convos.messaging.conversationRepository(for: conversationId),
        messageWriter: convos.messaging.messageWriter(for: conversationId),
        messagesRepository: convos.messaging.messagesRepository(for: conversationId)
    )
    .ignoresSafeArea()
}
