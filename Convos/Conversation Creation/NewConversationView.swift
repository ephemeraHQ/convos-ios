import ConvosCore
import SwiftUI

struct NewConversationView: View {
    let viewModel: NewConversationViewModel
    @State private var hasShownScannerOnAppear: Bool = false
    @State private var presentingDeleteConfirmation: Bool = false
    @State private var presentingJoiningStateInfo: Bool = false
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
                            messagesTextFieldEnabled: viewModel.messagesTextFieldEnabled,
                        ) {
                        }
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button(role: .close) {
                                    if viewModel.shouldConfirmDeletingConversation {
                                        presentingDeleteConfirmation = true
                                    } else if viewModel.conversationViewModel.onboardingCoordinator.isWaitingForInviteAcceptance {
                                        presentingJoiningStateInfo = true
                                    } else {
                                        dismiss()
                                    }
                                }
                                .confirmationDialog("This convo will appear on your home screen after someone approves you",
                                                    isPresented: $presentingJoiningStateInfo,
                                                    titleVisibility: .visible) {
                                    Button("Continue") {
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
                .selfSizingSheet(item: $viewModel.displayError) { error in
                    InfoView(title: error.title, description: error.description)
                }
            }
        }
    }
}

#Preview {
    @Previewable @State var viewModel: NewConversationViewModel = .init(
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
