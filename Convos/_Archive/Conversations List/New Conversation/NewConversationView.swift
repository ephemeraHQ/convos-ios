import SwiftUI

struct NewConversationView: View {
    let session: any SessionManagerProtocol
    @State private var draftConversationComposer: any DraftConversationComposerProtocol
    @State private var conversationState: ConversationState
    @State private var newConversationState: NewConversationState
    @Environment(\.dismiss) private var dismiss: DismissAction

    @State private var qrCodeIdentifier: String = "otr-invite"

    init(
        session: any SessionManagerProtocol
    ) {
        self.session = session
        let inbox = try? session.inboxesRepository.allInboxes().first(where: { $0.type == .standard })
        let messaging = session.messagingService(for: inbox?.inboxId ?? "")
        let draftConversationComposer = messaging.draftConversationComposer()
        _draftConversationComposer = State(initialValue: draftConversationComposer)
        let draftConversationRepo = draftConversationComposer.draftConversationRepository
        let composerState = NewConversationState(
            draftConversationRepo: draftConversationRepo,
            draftConversationWriter: draftConversationComposer.draftConversationWriter,
            conversationConsentWriter: draftConversationComposer.conversationConsentWriter,
            conversationLocalStateWriter: draftConversationComposer.conversationLocalStateWriter,
            messagesRepository: draftConversationRepo.messagesRepository
        )
        _newConversationState = State(initialValue: composerState)
        _conversationState = State(initialValue: ConversationState(
            conversationRepository: draftConversationRepo
        ))
    }

    var body: some View {
        NavigationStack {
            MessagesContainerView(
                conversationState: conversationState,
                outgoingMessageWriter: draftConversationComposer.draftConversationWriter,
                conversationConsentWriter: draftConversationComposer.conversationConsentWriter,
                conversationLocalStateWriter: draftConversationComposer.conversationLocalStateWriter
            ) {
                EmptyView()
                    .ignoresSafeArea()
//                ConversationComposerContentView(
//                    composerState: conversationComposerState,
//                    profileSearchText: $conversationComposerState.searchText,
//                    selectedProfile: $conversationComposerState.selectedProfile
//                )
//                .background(.clear)
//                .ignoresSafeArea()
            }
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .title) {
                    Button {

                    } label: {
                        HStack(spacing: DesignConstants.Spacing.step2x) {
                            ConversationAvatarView(conversation: .mock(name: ""))
                                .frame(width: 36.0, height: 36.0)

                            VStack(alignment: .leading) {
                                Text("New convo")
                                    .font(.system(size: 16.0, weight: .medium))
                                Text("Customize")
                                        .font(.system(size: 12.0, weight: .regular))
                                    .foregroundStyle(.colorTextSecondary)
                            }
                            .padding(.trailing, DesignConstants.Spacing.step2x)
                        }
                    }
                    .padding(DesignConstants.Spacing.step2x)
                    .glassEffect()
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
