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
                JoinConversationView(newConversationState: newConversationState, showsToolbar: true)
            }
            .onAppear {
                if !newConversationState.showScannerOnAppear {
                    newConversationState.newConversation()
                }
            }
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                if !newConversationState.showScannerOnAppear {
                    ToolbarItem(placement: .title) {
                        if let conversation = newConversationState.conversationState?.conversation {
                            Button {
                            } label: {
                                HStack(spacing: DesignConstants.Spacing.step2x) {
                                    ConversationAvatarView(conversation: conversation)
                                        .frame(width: 36.0, height: 36.0)

                                    VStack(alignment: .leading, spacing: 0.0) {
                                        if !conversation.isDraft, let name = conversation.name, !name.isEmpty {
                                            Text(name)
                                                .font(.system(size: 16.0, weight: .medium))
                                        } else {
                                            Text("New convo")
                                                .font(.system(size: 16.0, weight: .medium))
                                        }
                                        Text("Customize")
                                            .font(.system(size: 12.0, weight: .regular))
                                            .foregroundStyle(.colorTextSecondary)
                                    }
                                    .padding(.trailing, DesignConstants.Spacing.step2x)
                                }
                            }
                            .padding(.horizontal, DesignConstants.Spacing.step2x)
                            .padding(.vertical, DesignConstants.Spacing.stepX)
                            .glassEffect()
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
                            Button {
                                // invite
                            } label: {
                                Image(systemName: "square.and.arrow.up")
                            }
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
