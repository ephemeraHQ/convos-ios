import SwiftUI

struct ConversationView<MessagesBottomBar: View>: View {
    @Bindable var viewModel: ConversationViewModel
    @FocusState.Binding var focusState: MessagesViewInputFocus?
    let onScanInviteCode: () -> Void
    let onDeleteConversation: () -> Void
    let confirmDeletionBeforeDismissal: Bool
    let messagesTopBarTrailingItem: MessagesViewTopBarTrailingItem
    let messagesTopBarTrailingItemEnabled: Bool
    let messagesBottomBarEnabled: Bool
    @ViewBuilder let bottomBarContent: () -> MessagesBottomBar

    @State private var presentingShareView: Bool = false
    @Environment(\.dismiss) private var dismiss: DismissAction

    var body: some View {
        MessagesView(
            conversation: viewModel.conversation,
            messages: viewModel.messages,
            invite: viewModel.invite,
            profile: viewModel.profile,
            untitledConversationPlaceholder: viewModel.untitledConversationPlaceholder,
            conversationNamePlaceholder: viewModel.conversationNamePlaceholder,
            conversationName: $viewModel.editingConversationName,
            conversationImage: $viewModel.conversationImage,
            displayName: $viewModel.editingDisplayName,
            messageText: $viewModel.messageText,
            sendButtonEnabled: $viewModel.sendButtonEnabled,
            profileImage: $viewModel.profileImage,
            focusState: $focusState,
            messagesBottomBarEnabled: messagesBottomBarEnabled,
            viewModelFocus: viewModel.focus,
            onConversationInfoTap: viewModel.onConversationInfoTap,
            onConversationNameEndedEditing: viewModel.onConversationNameEndedEditing,
            onConversationSettings: viewModel.onConversationSettings,
            onProfilePhotoTap: viewModel.onProfilePhotoTap,
            onSendMessage: viewModel.onSendMessage,
            onTapMessage: viewModel.onTapMessage(_:),
            onDisplayNameEndedEditing: viewModel.onDisplayNameEndedEditing,
            onProfileSettings: viewModel.onProfileSettings,
            bottomBarContent: bottomBarContent
        )
        .selfSizingSheet(isPresented: $viewModel.presentingConversationForked) {
            ConversationForkedInfoView {
                viewModel.leaveConvo()
            }
        }
        .sheet(isPresented: $viewModel.presentingProfileSettings) {
            ProfileView(viewModel: viewModel)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                switch messagesTopBarTrailingItem {
                case .share:
                    Button {
                        presentingShareView = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundStyle(.colorTextPrimary)
                    }
                    .fullScreenCover(isPresented: $presentingShareView) {
                        ConversationShareView(conversation: viewModel.conversation, invite: viewModel.invite)
                            .presentationBackground(.clear)
                    }
                    .disabled(!messagesTopBarTrailingItemEnabled)
                    .transaction { transaction in
                        transaction.disablesAnimations = true
                    }
                case .scan:
                    Button {
                        onScanInviteCode()
                    } label: {
                        Image(systemName: "qrcode.viewfinder")
                    }
                    .buttonBorderShape(.circle)
                    .disabled(!messagesTopBarTrailingItemEnabled)
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
    NavigationStack {
        ConversationView(
            viewModel: viewModel,
            focusState: $focusState,
            onScanInviteCode: {},
            onDeleteConversation: {},
            confirmDeletionBeforeDismissal: true,
            messagesTopBarTrailingItem: .share,
            messagesTopBarTrailingItemEnabled: true,
            messagesBottomBarEnabled: true,
            bottomBarContent: { EmptyView() }
        )
    }
}
