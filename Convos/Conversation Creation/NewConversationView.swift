import ConvosCore
import SwiftUI

struct InviteShareLink: View {
    let invite: Invite?
    var body: some View {
        let inviteString = invite?.inviteUrlString ?? ""
        ShareLink(
            item: inviteString,
            preview: SharePreview(
                "Join a private convo",
                image: Image("AppIcon")
            )
        ) {
            Image(systemName: "square.and.arrow.up")
                .foregroundStyle(.colorTextPrimary)
        }
        .disabled(inviteString.isEmpty)
    }
}

struct NewConversationView: View {
    let viewModel: NewConversationViewModel
    @State private var hasShownScannerOnAppear: Bool = false
    @State private var presentingDeleteConfirmation: Bool = false
    @State private var sidebarWidth: CGFloat = 0.0

    @FocusState private var focusState: MessagesViewInputFocus?

    @Environment(\.dismiss) private var dismiss: DismissAction

    var body: some View {
        ConversationInfoPresenter(
            viewModel: viewModel.conversationViewModel,
            focusState: $focusState,
            sidebarColumnWidth: $sidebarWidth,
        ) {
            NavigationStack {
                @Bindable var viewModel = viewModel
                Group {
                    if viewModel.showingFullScreenScanner {
                        JoinConversationView(allowsDismissal: viewModel.allowsDismissingScanner) { inviteCode in
                            viewModel.validateAndJoin(inviteUrlString: inviteCode)
                        }
                    } else {
                        let conversationViewModel = viewModel.conversationViewModel
                        ConversationView(
                            viewModel: conversationViewModel,
                            focusState: $focusState,
                            onScanInviteCode: viewModel.onScanInviteCode,
                            onDeleteConversation: viewModel.deleteConversation,
                            confirmDeletionBeforeDismissal: viewModel.shouldConfirmDeletingConversation,
                            messagesTopBarTrailingItem: viewModel.messagesTopBarTrailingItem
                        )
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button(role: .close) {
                                    if viewModel.shouldConfirmDeletingConversation {
                                        presentingDeleteConfirmation = true
                                    } else {
                                        dismiss()
                                    }
                                }
                                .confirmationDialog("", isPresented: $presentingDeleteConfirmation) {
                                    Button("Delete", role: .destructive) {
                                        viewModel.deleteConversation()
                                        dismiss()
                                    }

                                    Button("Keep") {
                                        dismiss()
                                    }
                                }
                            }
                        }
                    }
                }
                .background(.colorBackgroundPrimary)
                .sheet(isPresented: $viewModel.presentingJoinConversationSheet) {
                    JoinConversationView { inviteCode in
                        viewModel.validateAndJoin(inviteUrlString: inviteCode)
                    }
                }
                .selfSizingSheet(isPresented: $viewModel.presentingInvalidInviteSheet) {
                    InfoView(title: "No convo here", description: "Maybe it already exploded.")
                }
                .selfSizingSheet(isPresented: $viewModel.presentingFailedToJoinSheet) {
                    InfoView(title: "Try again", description: "Joining the convo failed.")
                }
            }
        }
    }
}

#Preview {
    @Previewable @State var viewModel: NewConversationViewModel = .init(
        session: ConvosClient.mock().session,
        showingFullScreenScanner: false
    )
    @Previewable @State var presented: Bool = true
    VStack {
    }
    .fullScreenCover(isPresented: $presented) {
        NewConversationView(viewModel: viewModel)
    }
}
