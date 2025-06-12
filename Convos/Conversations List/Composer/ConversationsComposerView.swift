import SwiftUI

struct ConversationComposerView: View {
    @State private var draftConversationComposer: any DraftConversationComposerProtocol
    @State private var conversationState: ConversationState
    @State private var conversationComposerState: ConversationComposerState

    init(
        draftConversationComposer: any DraftConversationComposerProtocol
    ) {
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
        }
    }
}

#Preview {
    ConversationComposerView(
        draftConversationComposer: MockDraftConversationComposer()
    )
    .ignoresSafeArea()
}
