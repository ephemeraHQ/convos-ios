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
        let inbox = try? session.inboxesRepository.allInboxes().first
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
                .ignoresSafeArea()
            }
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbar {
                ToolbarItemGroup(placement: .title) {
                    MessagesToolbarView(
                        conversationState: conversationState,
                    )
                }

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
    let convos = ConvosClient.mock()
    ConversationComposerView(
        session: convos.session
    )
    .ignoresSafeArea()
}
