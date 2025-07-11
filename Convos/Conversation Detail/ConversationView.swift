import SwiftUI

struct ConversationView: View {
    let conversationRepository: any ConversationRepositoryProtocol
    let messagesRepository: any MessagesRepositoryProtocol
    let outgoingMessageWriter: any OutgoingMessageWriterProtocol
    let conversationConsentWriter: any ConversationConsentWriterProtocol
    let conversationLocalStateWriter: any ConversationLocalStateWriterProtocol
    let messagingService: any MessagingServiceProtocol
    let conversationState: ConversationState
    let userState: UserState
    @State private var showInfo: Bool = false

    init(
        conversationRepository: any ConversationRepositoryProtocol,
        messagesRepository: any MessagesRepositoryProtocol,
        outgoingMessageWriter: any OutgoingMessageWriterProtocol,
        conversationConsentWriter: any ConversationConsentWriterProtocol,
        conversationLocalStateWriter: any ConversationLocalStateWriterProtocol,
        messagingService: any MessagingServiceProtocol
    ) {
        self.conversationRepository = conversationRepository
        self.messagesRepository = messagesRepository
        self.outgoingMessageWriter = outgoingMessageWriter
        self.conversationConsentWriter = conversationConsentWriter
        self.conversationLocalStateWriter = conversationLocalStateWriter
        self.messagingService = messagingService
        self.conversationState = ConversationState(conversationRepository: conversationRepository)
        self.userState = UserState(userRepository: messagingService.userRepository())
    }

    var body: some View {
        let infoTapAction = { showInfo = true }

        MessagesContainerView(
            conversationState: conversationState,
            outgoingMessageWriter: outgoingMessageWriter,
            conversationConsentWriter: conversationConsentWriter,
            conversationLocalStateWriter: conversationLocalStateWriter,
            onInfoTap: infoTapAction
        ) {
            MessagesView(
                messagesRepository: messagesRepository
            )
            .ignoresSafeArea()
        }
        .navigationDestination(isPresented: $showInfo) {
            ConversationInfoView(
                userState: userState,
                conversationState: conversationState,
                messagingService: messagingService
            )
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
        conversationLocalStateWriter: convos.messaging.conversationLocalStateWriter(),
        messagingService: convos.messaging
    )
    .ignoresSafeArea()
}
