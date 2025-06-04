import SwiftUI

struct MessagesView: UIViewControllerRepresentable {
    let messagesRepository: any MessagesRepositoryProtocol

    func makeUIViewController(context: Context) -> MessagesViewController {
        let messageViewController = MessagesViewController(
            messagesRepository: messagesRepository
        )
        return messageViewController
    }

    func updateUIViewController(_ messagesViewController: MessagesViewController, context: Context) {
    }
}

#Preview {
    let convos = ConvosClient.mock()
    let conversationId: String = "1"
    MessagesView(
        messagesRepository: convos.messaging.messagesRepository(for: conversationId)
    )
    .ignoresSafeArea()
}
