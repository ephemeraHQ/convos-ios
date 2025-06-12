import SwiftUI

struct ConversationView: View {
    let conversationRepository: any ConversationRepositoryProtocol
    let messagesRepository: any MessagesRepositoryProtocol
    let outgoingMessageWriter: any OutgoingMessageWriterProtocol
    let conversationConsentWriter: any ConversationConsentWriterProtocol
    let conversationLocalStateWriter: any ConversationLocalStateWriterProtocol
    let conversationState: ConversationState

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
        ) { textBinding in
            MessagesView(
                messagesRepository: messagesRepository,
                textBinding: textBinding
            )
            .ignoresSafeArea()
        }
    }
}

#Preview {
    let convos = ConvosClient.mock()
    let conversationId: String = "1"
    ConversationView(
        conversationRepository: convos.messaging.conversationRepository(for: conversationId),
        messagesRepository: convos.messaging.messagesRepository(for: conversationId),
        outgoingMessageWriter: convos.messaging.messageWriter(for: conversationId),
        conversationConsentWriter: convos.messaging.conversationConsentWriter(),
        conversationLocalStateWriter: convos.messaging.conversationLocalStateWriter()
    )
    .ignoresSafeArea()
}
