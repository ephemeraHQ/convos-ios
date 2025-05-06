import SwiftUI

struct MessagesView: UIViewControllerRepresentable {
    let messagesStore: MessagesStoreProtocol

    func makeUIViewController(context: Context) -> MessagesViewController {
        let messageViewController = MessagesViewController(messagesStore: messagesStore)
        return messageViewController
    }

    func updateUIViewController(_ uiViewController: MessagesViewController, context: Context) {
    }
}

#Preview {
    MessagesView(messagesStore: MockMessagesStore())
        .ignoresSafeArea()
}
