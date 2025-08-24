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
    @Bindable var viewModel: ConversationViewModel
    @FocusState.Binding var focusState: MessagesViewInputFocus?
    let onScanInviteCode: () -> Void
    let onDeleteConversation: () -> Void
    let confirmDeletionBeforeDismissal: Bool
    let messagesTopBarTrailingItem: MessagesView.TopBarTrailingItem

    @Environment(\.dismiss) private var dismiss: DismissAction

    init(
        viewModel: ConversationViewModel,
        focusState: FocusState<MessagesViewInputFocus?>.Binding,
        onScanInviteCode: @escaping () -> Void = {},
        onDeleteConversation: @escaping () -> Void = {},
        confirmDeletionBeforeDismissal: Bool = false,
        messagesTopBarTrailingItem: MessagesView.TopBarTrailingItem = .share
    ) {
        self.viewModel = viewModel
        self._focusState = focusState
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
            viewModelFocus: viewModel.focus,
            onConversationInfoTap: viewModel.onConversationInfoTap,
            onConversationNameEndedEditing: viewModel.onConversationNameEndedEditing,
            onConversationSettings: viewModel.onConversationSettings,
            onProfilePhotoTap: viewModel.onProfilePhotoTap,
            onSendMessage: viewModel.onSendMessage,
            onTapMessage: viewModel.onTapMessage(_:),
            onDisplayNameEndedEditing: viewModel.onDisplayNameEndedEditing,
            onProfileSettings: viewModel.onProfileSettings,
            onScanInviteCode: onScanInviteCode,
            onDeleteConversation: onDeleteConversation,
            confirmDeletionBeforeDismissal: confirmDeletionBeforeDismissal
        )
        .sheet(isPresented: $viewModel.presentingProfileSettings) {
            ProfileView(viewModel: viewModel)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                switch messagesTopBarTrailingItem {
                case .share:
                    InviteShareLink(invite: viewModel.invite)
                case .scan:
                    Button {
                        onScanInviteCode()
                    } label: {
                        Image(systemName: "qrcode.viewfinder")
                    }
                    .buttonBorderShape(.circle)
                }
            }
        }
        .sheet(item: $viewModel.presentingProfileForMember) { member in
            NavigationStack {
                ConversationMemberView(viewModel: viewModel, member: member)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(role: .cancel) {
                                viewModel.presentingProfileForMember = nil
                            }
                        }
                    }
            }
        }
        .onAppear(perform: viewModel.onAppear)
        .onDisappear(perform: viewModel.onDisappear)
        .onChange(of: viewModel.focus) {
            focusState = viewModel.focus
        }
        .onChange(of: focusState) {
            viewModel.focus = focusState
        }
    }
}

#Preview {
    @Previewable @State var viewModel: ConversationViewModel = .mock
    @Previewable @FocusState var focusState: MessagesViewInputFocus?
    ConversationView(viewModel: viewModel, focusState: $focusState)
}
