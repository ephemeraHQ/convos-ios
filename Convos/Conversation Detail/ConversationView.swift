import SwiftUI

struct ConversationView: View {
    let conversationRepository: any ConversationRepositoryProtocol
    let messagesRepository: any MessagesRepositoryProtocol
    let outgoingMessageWriter: any OutgoingMessageWriterProtocol
    let conversationConsentWriter: any ConversationConsentWriterProtocol
    let conversationLocalStateWriter: any ConversationLocalStateWriterProtocol
    let groupMetadataWriter: any GroupMetadataWriterProtocol
    let conversationState: ConversationState
    @State private var showInfoForConversation: Conversation?

    init(
        conversationRepository: any ConversationRepositoryProtocol,
        messagesRepository: any MessagesRepositoryProtocol,
        outgoingMessageWriter: any OutgoingMessageWriterProtocol,
        conversationConsentWriter: any ConversationConsentWriterProtocol,
        conversationLocalStateWriter: any ConversationLocalStateWriterProtocol,
        groupMetadataWriter: any GroupMetadataWriterProtocol
    ) {
        self.conversationRepository = conversationRepository
        self.messagesRepository = messagesRepository
        self.outgoingMessageWriter = outgoingMessageWriter
        self.conversationConsentWriter = conversationConsentWriter
        self.conversationLocalStateWriter = conversationLocalStateWriter
        self.groupMetadataWriter = groupMetadataWriter
        self.conversationState = ConversationState(conversationRepository: conversationRepository)
    }

    var body: some View {
        MessagesContainerView(
            conversationState: conversationState,
            outgoingMessageWriter: outgoingMessageWriter,
            conversationConsentWriter: conversationConsentWriter,
            conversationLocalStateWriter: conversationLocalStateWriter
        ) {
            MessagesView(
                messagesRepository: messagesRepository
            )
            .ignoresSafeArea()
        }
        .navigationDestination(item: $showInfoForConversation) { conversation in
            ConversationInfoView(
                conversation: conversation,
                groupMetadataWriter: groupMetadataWriter
            )
        }
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .title) {
                Button {
                    showInfoForConversation = conversationState.conversation
                } label: {
                    MessagesToolbarView(
                        conversationState: conversationState,
                    )
                }
            }
        }
    }
}

#Preview {
    let messaging = MockMessagingService()
    let conversationId: String = "1"
    ConversationView(
        conversationRepository: messaging.conversationRepository(for: conversationId),
        messagesRepository: messaging.messagesRepository(for: conversationId),
        outgoingMessageWriter: messaging.messageWriter(for: conversationId),
        conversationConsentWriter: messaging.conversationConsentWriter(),
        conversationLocalStateWriter: messaging.conversationLocalStateWriter(),
        groupMetadataWriter: messaging.groupMetadataWriter()
    )
    .ignoresSafeArea()
}
