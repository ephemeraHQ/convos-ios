import SwiftUI

struct NewConversationView: View {
    let session: any SessionManagerProtocol
    @State private var newConversationState: NewConversationState
    @State private var presentingDeleteConfirmation: Bool = false
    @Environment(\.dismiss) private var dismiss: DismissAction

    init(
        session: any SessionManagerProtocol
    ) {
        self.session = session
        _newConversationState = .init(initialValue: .init(session: session))
    }

    var body: some View {
        NavigationStack {
            Group {
                if let conversationState = newConversationState.conversationState,
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
            .onAppear {
                newConversationState.newConversation()
            }
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
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

                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .close) {
                        if newConversationState.promptToKeepConversation {
                            presentingDeleteConfirmation = true
                        } else {
                            dismiss()
                        }
                    }
                    .confirmationDialog("", isPresented: $presentingDeleteConfirmation) {
                        Button("Delete", role: .destructive) {
                            do {
                                try newConversationState.deleteConversation()
                            } catch {
                                Logger.error("Error deleting conversation: \(error.localizedDescription)")
                            }
                            dismiss()
                        }

                        Button("Keep") {
                            dismiss()
                        }
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if newConversationState.showJoinConversation {
                        Button {
                            //
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

#Preview {
    @Previewable @State var presented: Bool = true
    let convos = ConvosClient.mock()
    VStack {
    }
    .fullScreenCover(isPresented: $presented) {
        NewConversationView(
            session: convos.session
        )
        .ignoresSafeArea()
    }
}
