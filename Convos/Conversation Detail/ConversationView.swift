import SwiftUI

/// This allows the interactive swipe to go back gesture while hiding the toolbar
struct SwipeBackGestureEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        DispatchQueue.main.async {
            uiViewController.navigationController?.interactivePopGestureRecognizer?.isEnabled = true
            uiViewController.navigationController?.interactivePopGestureRecognizer?.delegate = nil
        }
    }
}

struct ConversationView: View {
    @State var viewModel: ConversationViewModel
    let onScanInviteCode: () -> Void
    let onDeleteConversation: () -> Void
    let confirmDeletionBeforeDismissal: Bool
    let messagesTopBarTrailingItem: MessagesTopBar.TrailingItem

    @FocusState private var focusState: MessagesViewInputFocus?

    init(
        viewModel: ConversationViewModel,
        onScanInviteCode: @escaping () -> Void = {},
        onDeleteConversation: @escaping () -> Void = {},
        confirmDeletionBeforeDismissal: Bool = false,
        messagesTopBarTrailingItem: MessagesTopBar.TrailingItem = .share
    ) {
        self.viewModel = viewModel
        self.onScanInviteCode = onScanInviteCode
        self.onDeleteConversation = onDeleteConversation
        self.confirmDeletionBeforeDismissal = confirmDeletionBeforeDismissal
        self.messagesTopBarTrailingItem = messagesTopBarTrailingItem
    }

    var body: some View {
        MessagesView(
            conversation: viewModel.conversation,
            messages: viewModel.messages,
            invite: viewModel.invite,
            profile: viewModel.profile,
            untitledConversationPlaceholder: viewModel.untitledConversationPlaceholder,
            conversationNamePlaceholder: viewModel.conversationNamePlaceholder,
            conversationName: $viewModel.conversationName,
            conversationImage: $viewModel.conversationImage,
            displayName: $viewModel.displayName,
            messageText: $viewModel.messageText,
            sendButtonEnabled: $viewModel.sendButtonEnabled,
            profileImage: $viewModel.profileImage,
            focusState: $focusState,
            onConversationInfoTap: viewModel.onConversationInfoTap,
            onConversationNameEndedEditing: viewModel.onConversationNameEndedEditing,
            onConversationSettings: viewModel.onConversationSettings,
            onProfilePhotoTap: viewModel.onProfilePhotoTap,
            onSendMessage: viewModel.onSendMessage,
            onDisplayNameEndedEditing: viewModel.onDisplayNameEndedEditing,
            onProfileSettings: viewModel.onProfileSettings,
            onScanInviteCode: onScanInviteCode,
            onDeleteConversation: onDeleteConversation,
            topBarLeadingItem: .back,
            topBarTrailingItem: messagesTopBarTrailingItem,
            confirmDeletionBeforeDismissal: confirmDeletionBeforeDismissal
        )
        .onAppear(perform: viewModel.onAppear)
        .onDisappear(perform: viewModel.onDisappear)
        .onChange(of: viewModel.focus) { _, newValue in
            focusState = newValue
        }
        .toolbarVisibility(.hidden, for: .navigationBar)
        .background(SwipeBackGestureEnabler())
    }
}

#Preview {
    @Previewable @State var viewModel: ConversationViewModel = .mock
    ConversationView(viewModel: viewModel)
}
