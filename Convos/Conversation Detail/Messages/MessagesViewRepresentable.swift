import ConvosCore
import SwiftUI

struct MessagesViewRepresentable: UIViewControllerRepresentable {
    let conversation: Conversation
    let messages: [AnyMessage]
    let invite: Invite
    let onTapMessage: (AnyMessage) -> Void
    let onTapAvatar: (AnyMessage) -> Void
    let bottomBarHeight: CGFloat

    func makeUIViewController(context: Context) -> MessagesViewController {
        return MessagesViewController()
    }

    func updateUIViewController(_ messagesViewController: MessagesViewController, context: Context) {
        messagesViewController.bottomBarHeight = bottomBarHeight
        messagesViewController.onTapMessage = onTapMessage
        messagesViewController.onTapAvatar = onTapAvatar
        messagesViewController.state = .init(
            conversation: conversation,
            messages: messages,
            invite: invite
        )
    }
}

#Preview {
    @Previewable @State var bottomBarHeight: CGFloat = 0.0
    let messages: [AnyMessage] = []
    let invite: Invite = .empty

    MessagesViewRepresentable(
        conversation: .mock(),
        messages: messages,
        invite: invite,
        onTapMessage: { _ in },
        onTapAvatar: { _ in },
        bottomBarHeight: bottomBarHeight
    )
    .ignoresSafeArea()
}
