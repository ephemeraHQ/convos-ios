import SwiftUI

struct MessagesView: UIViewControllerRepresentable {
    let messagingService: MessagingServiceProtocol

    func makeUIViewController(context: Context) -> MessagesViewController {
        let messageViewController = MessagesViewController(messagingService: messagingService)
        return messageViewController
    }

    func updateUIViewController(_ uiViewController: MessagesViewController, context: Context) {
    }
}

#Preview {
    MessagesView(messagingService: MockMessagingService())
        .ignoresSafeArea()
}
