import SwiftUI

struct MessagesViewRepresentable: UIViewControllerRepresentable {
    let conversationId: String
    let messages: [AnyMessage]
    let invite: Invite
    let topBarHeight: CGFloat
    let bottomBarHeight: CGFloat

    func makeUIViewController(context: Context) -> MessagesViewController {
        let messagesViewController = MessagesViewController()
        messagesViewController.topBarHeight = topBarHeight
        messagesViewController.bottomBarHeight = bottomBarHeight
        messagesViewController.state = .init(conversationId: conversationId, messages: messages, invite: invite)
        return messagesViewController
    }

    func updateUIViewController(_ messagesViewController: MessagesViewController, context: Context) {
        messagesViewController.topBarHeight = topBarHeight
        messagesViewController.bottomBarHeight = bottomBarHeight
        messagesViewController.state = .init(conversationId: conversationId, messages: messages, invite: invite)
    }
}

#Preview {
    @Previewable @State var topBarHeight: CGFloat = 0.0
    @Previewable @State var bottomBarHeight: CGFloat = 0.0
    let conversationId: String = "1"
    let messages: [AnyMessage] = []
    let invite: Invite = .empty

    MessagesViewRepresentable(
        conversationId: conversationId,
        messages: messages,
        invite: invite,
        topBarHeight: topBarHeight,
        bottomBarHeight: bottomBarHeight
    )
    .ignoresSafeArea()
}
