import SwiftUI

struct MessagesView: UIViewControllerRepresentable {
    let conversationRepository: any ConversationRepositoryProtocol
    let outgoingMessageWriter: any OutgoingMessageWriterProtocol
    @State private var conversationState: ConversationState

    init(conversationRepository: any ConversationRepositoryProtocol,
         outgoingMessageWriter: any OutgoingMessageWriterProtocol) {
        self.conversationRepository = conversationRepository
        self.outgoingMessageWriter = outgoingMessageWriter
        _conversationState = State(
            initialValue: .init(
                conversationRepository: conversationRepository
            )
        )
    }

    func makeUIViewController(context: Context) -> MessagesViewController {
        let messageViewController = MessagesViewController(
            conversationRepository: conversationRepository,
            outgoingMessageWriter: outgoingMessageWriter
        )
        return messageViewController
    }

    func updateUIViewController(_ messagesViewController: MessagesViewController, context: Context) {
            messagesViewController
                .navigationBar
                .configure(
                    conversation: conversationState.conversation
                )
    }
}

#Preview {
    let convos = ConvosClient.mock()
    let conversationId: String = "1"
    MessagesView(
        conversationRepository: convos.messaging.conversationRepository(for: conversationId),
        outgoingMessageWriter: convos.messaging.messageWriter(for: conversationId)
    )
    .ignoresSafeArea()
}
