import ConvosCore
import SwiftUI

struct InviteShareLink: View {
    let invite: Invite?
    var body: some View {
        let inviteString = invite?.inviteURLString ?? ""
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

struct InviteAcceptedView: View {
    @State private var showingDescription: Bool = false

    var body: some View {
        VStack(spacing: DesignConstants.Spacing.step2x) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14.0))
                    .foregroundStyle(.colorGreen)
                Text("Invite accepted")
                    .foregroundStyle(.colorTextPrimary)
            }
            .font(.body)

            if showingDescription {
                Text("See and send messages after someone approves you.")
                    .font(.caption)
                    .foregroundStyle(.colorTextSecondary)
            }
        }
        .padding(.horizontal, DesignConstants.Spacing.step10x)
        .padding(.bottom, DesignConstants.Spacing.step4x)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation {
                    self.showingDescription = true
                }
            }
        }
    }
}

#Preview {
    InviteAcceptedView()
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
                        JoinConversationView(
                            viewModel: viewModel.qrScannerViewModel,
                            allowsDismissal: viewModel.allowsDismissingScanner,
                            onScannedCode: { inviteCode in
                                viewModel.joinConversation(inviteCode: inviteCode)
                            }
                        )
                    } else {
                        let conversationViewModel = viewModel.conversationViewModel
                        ConversationView(
                            viewModel: conversationViewModel,
                            focusState: $focusState,
                            onScanInviteCode: viewModel.onScanInviteCode,
                            onDeleteConversation: viewModel.deleteConversation,
                            confirmDeletionBeforeDismissal: viewModel.shouldConfirmDeletingConversation,
                            messagesTopBarTrailingItem: viewModel.messagesTopBarTrailingItem,
                            messagesTopBarTrailingItemEnabled: viewModel.messagesTopBarTrailingItemEnabled,
                            messagesBottomBarEnabled: viewModel.messagesBottomBarEnabled
                        ) {
                            if viewModel.isWaitingForInviteAcceptance {
                                InviteAcceptedView()
                            }
                        }
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
                    JoinConversationView(viewModel: viewModel.qrScannerViewModel, allowsDismissal: true) { inviteCode in
                        viewModel.joinConversation(inviteCode: inviteCode)
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
    // swiftlint:disable:next force_try
    @Previewable @State var viewModel: NewConversationViewModel = try! .init(
        session: ConvosClient.mock().session,
        messagingService: MockMessagingService(),
        showingFullScreenScanner: false
    )
    @Previewable @State var presented: Bool = true
    VStack {
    }
    .fullScreenCover(isPresented: $presented) {
        NewConversationView(viewModel: viewModel)
    }
}
