import SwiftUI

struct NewConversationView: View {
    let session: any SessionManagerProtocol
    @State private var newConversationState: NewConversationState
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
                        outgoingMessageWriter: composer.draftConversationWriter,
                        conversationLocalStateWriter: composer.conversationLocalStateWriter
                    ) {
                        MessagesView(messagesRepository: composer.draftConversationRepository.messagesRepository)
                            .ignoresSafeArea()
                    }
                } else {
                    EmptyView()
                        .ignoresSafeArea()
                }
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
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        //
                    } label: {
                        Image(systemName: "qrcode.viewfinder")
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
