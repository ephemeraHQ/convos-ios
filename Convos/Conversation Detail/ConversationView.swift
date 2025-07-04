import SwiftUI

struct ConversationView: View {
    let conversationRepository: any ConversationRepositoryProtocol
    let messagesRepository: any MessagesRepositoryProtocol
    let outgoingMessageWriter: any OutgoingMessageWriterProtocol
    let conversationConsentWriter: any ConversationConsentWriterProtocol
    let conversationLocalStateWriter: any ConversationLocalStateWriterProtocol
    let conversationState: ConversationState
    @State private var showInfo: Bool = false

    init(
        conversationRepository: any ConversationRepositoryProtocol,
        messagesRepository: any MessagesRepositoryProtocol,
        outgoingMessageWriter: any OutgoingMessageWriterProtocol,
        conversationConsentWriter: any ConversationConsentWriterProtocol,
        conversationLocalStateWriter: any ConversationLocalStateWriterProtocol
    ) {
        self.conversationRepository = conversationRepository
        self.messagesRepository = messagesRepository
        self.outgoingMessageWriter = outgoingMessageWriter
        self.conversationConsentWriter = conversationConsentWriter
        self.conversationLocalStateWriter = conversationLocalStateWriter
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
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .title) {
                Button {
                    showInfo = true
                } label: {
                    MessagesToolbarView(
                        conversationState: conversationState,
                    )
                }
            }
        }
        .sheet(isPresented: $showInfo) {
            ConversationInfoView()
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
        conversationLocalStateWriter: messaging.conversationLocalStateWriter()
    )
    .ignoresSafeArea()
}
