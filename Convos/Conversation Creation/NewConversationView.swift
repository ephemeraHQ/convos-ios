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
                .font(.system(size: 20.0))
                .foregroundStyle(.colorTextPrimary)
        }
        .disabled(inviteString.isEmpty)
    }
}

struct NewConversationView: View {
    @State var viewModel: NewConversationViewModel
    @State private var hasShownScannerOnAppear: Bool = false
    @State private var presentingJoinConversationSheet: Bool = false

    var body: some View {
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
                        onScanInviteCode: {
                            presentingJoinConversationSheet = true
                        },
                        onDeleteConversation: viewModel.deleteConversation,
                        confirmDeletionBeforeDismissal: viewModel.shouldConfirmDeletingConversation,
                        messagesTopBarTrailingItem: viewModel.messagesTopBarTrailingItem
                    )
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
