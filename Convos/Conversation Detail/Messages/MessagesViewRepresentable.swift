import ConvosCore
import SwiftUI

struct MessagesViewRepresentable: UIViewControllerRepresentable {
    let conversation: Conversation
    let messages: [AnyMessage]
    let invite: Invite
    let onTapMessage: (AnyMessage) -> Void
    let topBarHeight: CGFloat
    let bottomBarHeight: CGFloat

    func makeUIViewController(context: Context) -> MessagesViewController {
        let messagesViewController = MessagesViewController()
        messagesViewController.state = .init(
            conversation: conversation,
            messages: messages,
            invite: invite
        )
        return messagesViewController
    }

    func updateUIViewController(_ messagesViewController: MessagesViewController, context: Context) {
        messagesViewController.topBarHeight = topBarHeight
        messagesViewController.bottomBarHeight = bottomBarHeight
        messagesViewController.onTapMessage = onTapMessage
        messagesViewController.state = .init(
            conversation: conversation,
            messages: messages,
            invite: invite
        )
    }
}

#Preview {
    @Previewable @State var topBarHeight: CGFloat = 0.0
    @Previewable @State var bottomBarHeight: CGFloat = 0.0
    let messages: [AnyMessage] = []
    let invite: Invite = .empty

    MessagesViewRepresentable(
        conversation: .mock(),
        messages: messages,
        invite: invite,
        onTapMessage: { _ in },
        topBarHeight: topBarHeight,
        bottomBarHeight: bottomBarHeight
    )
    .ignoresSafeArea()
}
