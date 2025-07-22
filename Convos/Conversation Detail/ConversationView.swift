import SwiftUI

struct ConversationViewDependencies: Hashable {
    let conversationId: String
    let conversationRepository: any ConversationRepositoryProtocol
    let messagesRepository: any MessagesRepositoryProtocol
    let outgoingMessageWriter: any OutgoingMessageWriterProtocol
    let conversationConsentWriter: any ConversationConsentWriterProtocol
    let conversationLocalStateWriter: any ConversationLocalStateWriterProtocol
    let groupMetadataWriter: any GroupMetadataWriterProtocol

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.conversationId == rhs.conversationId
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(conversationId)
    }
}

extension ConversationViewDependencies {
    static func mock() -> ConversationViewDependencies {
        let messaging = MockMessagingService()
        let conversationId: String = "1"
        return ConversationViewDependencies(
            conversationId: conversationId,
            conversationRepository: messaging.conversationRepository(for: conversationId),
            messagesRepository: messaging.messagesRepository(for: conversationId),
            outgoingMessageWriter: messaging.messageWriter(for: conversationId),
            conversationConsentWriter: messaging.conversationConsentWriter(),
            conversationLocalStateWriter: messaging.conversationLocalStateWriter(),
            groupMetadataWriter: messaging.groupMetadataWriter()
        )
    }
}

struct ConversationView: View {
    let conversationRepository: any ConversationRepositoryProtocol
    let messagesRepository: any MessagesRepositoryProtocol
    let outgoingMessageWriter: any OutgoingMessageWriterProtocol
    let conversationConsentWriter: any ConversationConsentWriterProtocol
    let conversationLocalStateWriter: any ConversationLocalStateWriterProtocol
    let groupMetadataWriter: any GroupMetadataWriterProtocol
    let conversationState: ConversationState
    @State private var showInfoForConversation: Conversation?

    init(dependencies: ConversationViewDependencies) {
        self.conversationRepository = dependencies.conversationRepository
        self.messagesRepository = dependencies.messagesRepository
        self.outgoingMessageWriter = dependencies.outgoingMessageWriter
        self.conversationConsentWriter = dependencies.conversationConsentWriter
        self.conversationLocalStateWriter = dependencies.conversationLocalStateWriter
        self.groupMetadataWriter = dependencies.groupMetadataWriter
        self.conversationState = ConversationState(conversationRepository: dependencies.conversationRepository)
    }

    var body: some View {
        MessagesContainerView(
            conversationState: conversationState,
            outgoingMessageWriter: outgoingMessageWriter,
            conversationLocalStateWriter: conversationLocalStateWriter
        ) {
            MessagesView(
                messagesRepository: messagesRepository
            )
            .ignoresSafeArea()
        }
//        .navigationDestination(item: $showInfoForConversation) { conversation in
//            ConversationInfoView(
//                conversation: conversation,
//                groupMetadataWriter: groupMetadataWriter
//            )
//        }
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
    ConversationView(dependencies: .mock())
        .ignoresSafeArea()
}
