import SwiftUI

struct MessagesView: UIViewControllerRepresentable {
    let conversationRepository: any ConversationRepositoryProtocol
    let outgoingMessageWriter: any OutgoingMessageWriterProtocol
    let messagesRepository: any MessagesRepositoryProtocol
    @State private var conversationState: ConversationState

    init(conversationRepository: ConversationRepositoryProtocol,
         outgoingMessageWriter: any OutgoingMessageWriterProtocol,
         messagesRepository: any MessagesRepositoryProtocol) {
        self.conversationRepository = conversationRepository
        self.outgoingMessageWriter = outgoingMessageWriter
        self.messagesRepository = messagesRepository
        _conversationState = State(
            initialValue: .init(
                conversationRepository: conversationRepository
            )
        )
    }

    func makeUIViewController(context: Context) -> MessagesViewController {
        let messageViewController = MessagesViewController(
            outgoingMessageWriter: outgoingMessageWriter,
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
        outgoingMessageWriter: convos.messaging.messageWriter(for: conversationId),
        messagesRepository: convos.messaging.messagesRepository(for: conversationId)
    )
    .ignoresSafeArea()
}
