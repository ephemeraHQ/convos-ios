import SwiftUI

struct NewConversationView: View {
    @Bindable var newConversationState: NewConversationState
    @State private var hasShownScannerOnAppear: Bool = false
    @State private var presentingJoinConversation: Bool = false
    @State private var presentingDeleteConfirmation: Bool = false
    @Environment(\.dismiss) private var dismiss: DismissAction

    var body: some View {
        NavigationStack {
            Group {
                if newConversationState.showScannerOnAppear && !hasShownScannerOnAppear {
                    JoinConversationView(newConversationState: newConversationState, showsToolbar: false) {
                        hasShownScannerOnAppear = true
                    }
                } else if let conversationState = newConversationState.conversationState,
                   let composer = newConversationState.draftConversationComposer {
                    MessagesContainerView(
                        conversationState: conversationState,
                        myProfileWriter: composer.myProfileWriter,
                        outgoingMessageWriter: composer.draftConversationWriter,
                        conversationLocalStateWriter: composer.conversationLocalStateWriter
                    ) {
                        MessagesView(
                            messagesRepository: composer.draftConversationRepository.messagesRepository,
                            inviteRepository: composer.draftConversationRepository.inviteRepository
                        )
                        .ignoresSafeArea()
                    }
                } else {
                    VStack(alignment: .center) {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .ignoresSafeArea()
                }
            }
            .background(.colorBackgroundPrimary)
            .ignoresSafeArea()
            .sheet(isPresented: $presentingJoinConversation) {
                JoinConversationView(
                    newConversationState: newConversationState,
                    showsToolbar: true
                ) {
                    presentingJoinConversation = false
                }
            }
            .onAppear {
                if !newConversationState.showScannerOnAppear {
                    newConversationState.newConversation()
                }
            }
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                if !newConversationState.showScannerOnAppear || hasShownScannerOnAppear {
                    if let conversation = newConversationState.conversationState?.conversation {
                        ToolbarItem(placement: .title) {
                            ConversationToolbarButton(conversation: conversation) {
                                // @jarodl show convo editor
                            }
                        }
                    }
                }

                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .close) {
                        if newConversationState.promptToKeepConversation && !newConversationState.showScannerOnAppear {
                            presentingDeleteConfirmation = true
                        } else {
                            dismiss()
                        }
                    }
                    .confirmationDialog("", isPresented: $presentingDeleteConfirmation) {
                        Button("Delete", role: .destructive) {
                            newConversationState.deleteConversation()
                            dismiss()
                        }

                        Button("Keep") {
                            dismiss()
                        }
                    }
                }

                if !newConversationState.showScannerOnAppear {
                    ToolbarItem(placement: .topBarTrailing) {
                        if newConversationState.showJoinConversation {
                            Button {
                                presentingJoinConversation = true
                            } label: {
                                Image(systemName: "qrcode.viewfinder")
                            }
                        } else {
                            let inviteString = newConversationState.conversationState?.conversation.invite?.temporaryInviteString ?? ""
                            ShareLink(
                                item: inviteString
                            ) {
                                Image(systemName: "square.and.arrow.up")
                            }
                            .disabled(inviteString.isEmpty)
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    @Previewable @State var state: NewConversationState = .init(
        session: ConvosClient.mock().session
    )
    @Previewable @State var presented: Bool = true
    VStack {
    }
    .fullScreenCover(isPresented: $presented) {
        NewConversationView(
            newConversationState: state
        )
        .ignoresSafeArea()
    }
}
