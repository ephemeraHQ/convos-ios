import SwiftUI

struct ConversationView: UIViewControllerRepresentable {
    let conversationRepository: any ConversationRepositoryProtocol
    let messagesRepository: any MessagesRepositoryProtocol
    let outgoingMessageWriter: any OutgoingMessageWriterProtocol

    func makeUIViewController(context: Context) -> MessagesContainerViewController {
        let messageContainerViewController = MessagesContainerViewController(
            conversationRepository: conversationRepository,
            outgoingMessageWriter: outgoingMessageWriter
        )
        let messagesViewController = MessagesViewController(
            messagesRepository: messagesRepository
        )
        messageContainerViewController.embedContentController(messagesViewController)
        return messageContainerViewController
    }

    func updateUIViewController(
        _ messagesContainerViewController: MessagesContainerViewController,
        context: Context) {
    }
}

#Preview {
    let convos = ConvosClient.mock()
    let conversationId: String = "1"
    ConversationView(
        conversationRepository: convos.messaging.conversationRepository(for: conversationId),
        messagesRepository: convos.messaging.messagesRepository(for: conversationId),
        outgoingMessageWriter: convos.messaging.messageWriter(for: conversationId)
    )
    .ignoresSafeArea()
}
