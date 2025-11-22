import ConvosCore
import SwiftUI

struct MessagesViewRepresentable: UIViewControllerRepresentable {
    let conversation: Conversation
    let messages: [MessagesListItemType]
    let invite: Invite
    let hasMoreMessages: Bool
    let onTapMessage: (AnyMessage) -> Void
    let onTapAvatar: (ConversationMember) -> Void
    let onLoadPreviousMessages: () -> Void
    let bottomBarHeight: CGFloat

    func makeUIViewController(context: Context) -> MessagesViewController {
        return MessagesViewController()
    }

    func updateUIViewController(_ messagesViewController: MessagesViewController, context: Context) {
        messagesViewController.bottomBarHeight = bottomBarHeight
        messagesViewController.onTapMessage = onTapMessage
        messagesViewController.onTapAvatar = onTapAvatar
        messagesViewController.onLoadPreviousMessages = onLoadPreviousMessages
        messagesViewController.state = .init(
            conversation: conversation,
            messages: messages,
            invite: invite,
            hasMoreMessages: hasMoreMessages
        )
    }
}

#Preview {
    @Previewable @State var bottomBarHeight: CGFloat = 0.0
    let messages: [MessagesListItemType] = []
    let invite: Invite = .empty

    MessagesViewRepresentable(
        conversation: .mock(),
        messages: messages,
        invite: invite,
        hasMoreMessages: true,
        onTapMessage: { _ in },
        onTapAvatar: { _ in },
        onLoadPreviousMessages: {},
        bottomBarHeight: bottomBarHeight
    )
    .ignoresSafeArea()
}
