import SwiftUI

struct ConversationComposerView: View {
    var body: some View {
        MessagesContainerView(
            conversationState: .init(conversationRepository: MockConversationRepository()),
            outgoingMessageWriter: MockOutgoingMessageWriter(),
            conversationConsentWriter: MockConversationConsentWriter(),
            conversationLocalStateWriter: MockConversationLocalStateWriter()
        ) {
            VStack {
            }
        }
    }
}

#Preview {
    ConversationComposerView()
}
