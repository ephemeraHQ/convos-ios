import SwiftUI

struct ConversationView: View {
    @Bindable var viewModel: ConversationViewModel
    @FocusState.Binding var focusState: MessagesViewInputFocus?
    let onScanInviteCode: () -> Void
    let onDeleteConversation: () -> Void
    let confirmDeletionBeforeDismissal: Bool
    let messagesTopBarTrailingItem: MessagesView.TopBarTrailingItem

    @Environment(\.dismiss) private var dismiss: DismissAction

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
    ConversationView(
        viewModel: viewModel,
        focusState: $focusState,
        onScanInviteCode: {},
        onDeleteConversation: {},
        confirmDeletionBeforeDismissal: true,
        messagesTopBarTrailingItem: .scan
    )
}
