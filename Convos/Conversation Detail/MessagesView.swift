import SwiftUI

struct MessagesView: UIViewControllerRepresentable {
    let messagesRepository: any MessagesRepositoryProtocol
    let textBinding: Binding<String>

    func makeUIViewController(context: Context) -> MessagesViewController {
        let messageViewController = MessagesViewController(
            messagesRepository: messagesRepository,
            textBinding: textBinding
        )
        return messageViewController
    }

    func updateUIViewController(_ messagesViewController: MessagesViewController, context: Context) {
    }
}

#Preview {
    @Previewable @State var text: String = ""
    let convos = ConvosClient.mock()
    let conversationId: String = "1"
    MessagesView(
        messagesRepository: convos.messaging.messagesRepository(for: conversationId),
        textBinding: $text
    )
}
