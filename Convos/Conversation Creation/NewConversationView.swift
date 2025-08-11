import SwiftUI

struct InviteShareLink: View {
    let invite: Invite?
    var body: some View {
        let inviteString = invite?.temporaryInviteString ?? ""
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
    @State private var presentingJoinConversationSheet: Bool = false
    @State private var presentingDeleteConfirmation: Bool = false
    @State private var sidebarWidth: CGFloat = 0.0

    @FocusState private var focusState: MessagesViewInputFocus?

    @Environment(\.dismiss) private var dismiss: DismissAction

    var body: some View {
        ConversationInfoPresenter(
            viewModel: viewModel,
            focusState: $focusState,
            sidebarColumnWidth: $sidebarWidth,
        ) {
            NavigationStack {
                Group {
                    if viewModel.showScannerOnAppear && !hasShownScannerOnAppear {
                        JoinConversationView { inviteCode in
                            hasShownScannerOnAppear = true
                            viewModel.join(inviteCode: inviteCode)
                        }
                    } else if let conversationViewModel = viewModel.conversationViewModel {
                        ConversationView(
                            viewModel: conversationViewModel,
                            focusState: $focusState,
                            onScanInviteCode: {
                                presentingJoinConversationSheet = true
                            },
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
                    } else {
                        VStack(alignment: .center) {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    }
                }
                .background(.colorBackgroundPrimary)
                .sheet(isPresented: $presentingJoinConversationSheet) {
                    JoinConversationView { inviteCode in
                        presentingJoinConversationSheet = false
                        viewModel.join(inviteCode: inviteCode)
                    }
                }
                .onAppear {
                    if !viewModel.showScannerOnAppear {
                        viewModel.newConversation()
                    }
                }
            }
        }
    }
}

#Preview {
    @Previewable @State var viewModel: NewConversationViewModel = .init(
        session: ConvosClient.mock().session,
        showScannerOnAppear: false
    )
    @Previewable @State var presented: Bool = true
    VStack {
    }
    .fullScreenCover(isPresented: $presented) {
        NewConversationView(viewModel: viewModel)
    }
}
