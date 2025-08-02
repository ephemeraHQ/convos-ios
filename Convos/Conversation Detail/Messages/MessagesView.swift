import SwiftUI

struct MessagesView: UIViewControllerRepresentable {
    let messagesRepository: any MessagesRepositoryProtocol
    let inviteRepository: any InviteRepositoryProtocol
    let inputViewHeight: CGFloat

    func makeUIViewController(context: Context) -> MessagesViewController {
        let messageViewController = MessagesViewController(
            messagesRepository: messagesRepository,
            inviteRepository: inviteRepository
        )
        messageViewController.inputViewHeight = inputViewHeight
        return messageViewController
    }

    func updateUIViewController(_ messagesViewController: MessagesViewController, context: Context) {
        messagesViewController.inputViewHeight = inputViewHeight
    }
}

#Preview {
    let messaging = MockMessagingService()
    let conversationId: String = "1"
    MessagesView(
        messagesRepository: messaging.messagesRepository(for: conversationId),
        inviteRepository: messaging.inviteRepository(for: conversationId),
        inputViewHeight: 0
    )
    .ignoresSafeArea()
}
