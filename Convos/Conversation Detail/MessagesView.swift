import SwiftUI

struct MessagesView: UIViewControllerRepresentable {
    let messagesRepository: any MessagesRepositoryProtocol
    let textBinding: Binding<String>
    let sendButtonEnabled: Binding<Bool>

    func makeUIViewController(context: Context) -> MessagesViewController {
        let messageViewController = MessagesViewController(
            messagesRepository: messagesRepository,
            textBinding: textBinding,
            sendButtonEnabled: sendButtonEnabled
        )
        return messageViewController
    }

    func updateUIViewController(_ messagesViewController: MessagesViewController, context: Context) {
    }
}

#Preview {
    @Previewable @State var text: String = ""
    @Previewable @State var sendButtonEnabled: Bool = true
    let convos = ConvosClient.mock()
    let conversationId: String = "1"
    MessagesView(
        messagesRepository: convos.messaging.messagesRepository(for: conversationId),
        textBinding: $text,
        sendButtonEnabled: $sendButtonEnabled
    )
}
