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
    let messaging = MockMessagingService()
    let conversationId: String = "1"
    MessagesView(
        messagesRepository: messaging.messagesRepository(for: conversationId)
    )
}
