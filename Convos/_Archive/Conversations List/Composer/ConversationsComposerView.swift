import SwiftUI

struct ConversationComposerView: View {
    let session: any SessionManagerProtocol
    @State private var draftConversationComposer: any DraftConversationComposerProtocol
    @State private var conversationState: ConversationState
    @State private var conversationComposerState: ConversationComposerState
    @Environment(\.dismiss) private var dismiss: DismissAction

    init(
        session: any SessionManagerProtocol
    ) {
        self.session = session
        let inbox = try? session.inboxesRepository.allInboxes().first(where: { $0.type == .standard })
        let messaging = session.messagingService(for: inbox?.inboxId ?? "")
        let draftConversationComposer = messaging.draftConversationComposer()
        _draftConversationComposer = State(initialValue: draftConversationComposer)
        let draftConversationRepo = draftConversationComposer.draftConversationRepository
        let composerState = ConversationComposerState(
            profileSearchRepository: draftConversationComposer.profileSearchRepository,
            draftConversationRepo: draftConversationRepo,
            draftConversationWriter: draftConversationComposer.draftConversationWriter,
            conversationConsentWriter: draftConversationComposer.conversationConsentWriter,
            conversationLocalStateWriter: draftConversationComposer.conversationLocalStateWriter,
            messagesRepository: draftConversationRepo.messagesRepository
        )
        _conversationComposerState = State(initialValue: composerState)
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
                ConversationComposerContentView(
                    composerState: conversationComposerState,
                    profileSearchText: $conversationComposerState.searchText,
                    selectedProfile: $conversationComposerState.selectedProfile
                )
                .background(.clear)
                .ignoresSafeArea()
            }
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) {
                        dismiss()
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
    .sheet(isPresented: $presented) {
        ConversationComposerView(
            session: convos.session
        )
        .ignoresSafeArea()
    }
}
