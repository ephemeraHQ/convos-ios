import SwiftUI

struct MessagesView: UIViewControllerRepresentable {
    let messagesRepository: any MessagesRepositoryProtocol
    let inviteRepository: any InviteRepositoryProtocol

    func makeUIViewController(context: Context) -> MessagesViewController {
        let messageViewController = MessagesViewController(
            messagesRepository: messagesRepository,
            inviteRepository: inviteRepository
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
        messagesRepository: messaging.messagesRepository(for: conversationId),
        inviteRepository: messaging.inviteRepository(for: conversationId)
    )
}
