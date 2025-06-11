import SwiftUI

struct ConversationView: UIViewControllerRepresentable {
    let conversationRepository: any ConversationRepositoryProtocol
    let messagesRepository: any MessagesRepositoryProtocol
    let outgoingMessageWriter: any OutgoingMessageWriterProtocol
    let conversationConsentWriter: any ConversationConsentWriterProtocol
    let conversationLocalStateWriter: any ConversationLocalStateWriterProtocol
    @Environment(\.dismiss) private var dismissAction: DismissAction

    func makeUIViewController(context: Context) -> MessagesContainerViewController {
        let messageContainerViewController = MessagesContainerViewController(
            conversationRepository: conversationRepository,
            outgoingMessageWriter: outgoingMessageWriter,
            conversationConsentWriter: conversationConsentWriter,
            conversationLocalStateWriter: conversationLocalStateWriter,
            dismissAction: dismissAction
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
        outgoingMessageWriter: convos.messaging.messageWriter(for: conversationId),
        conversationConsentWriter: convos.messaging.conversationConsentWriter(),
        conversationLocalStateWriter: convos.messaging.conversationLocalStateWriter()
    )
    .ignoresSafeArea()
}
