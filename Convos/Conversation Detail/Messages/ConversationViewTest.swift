import SwiftUI

struct ConversationViewTest: View {
    let conversationId: String = "1"
    static var messaging: any MessagingServiceProtocol = MockMessagingService()
    let messagesRepository: any MessagesRepositoryProtocol = Self.messaging.messagesRepository(for: "1")
    let inviteRepository: any InviteRepositoryProtocol = Self.messaging.inviteRepository(for: "1")

    var body: some View {
        GeometryReader { reader in
            NavigationStack {
                ZStack {
                    MessagesView(
                        messagesRepository: messagesRepository,
                        inviteRepository: inviteRepository
                    )
                    .toolbarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button(role: .cancel) {
                                //
                            }
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            InviteShareLink(invite: .mock())
                        }
                    }
                    .safeAreaBar(edge: .bottom) {
                        MessagesInputView(
                            viewModel: .init(myProfileWriter: MockMyProfileWriter(), outgoingMessageWriter: MockOutgoingMessageWriter()),
                            conversationState: .init(
                                myProfileRepository: MockMessagingService().myProfileRepository(),
                                conversationRepository: MockConversationRepository()
                            )
                        )
                    }

                    VStack {
                        Button {
                            //
                        } label: {
                            Text("Testing")
                                .padding()
                        }
                        .buttonStyle(GlassButtonStyle())
                        .zIndex(1000)
                        //                        ConversationToolbarButton(conversation: .mock(), action: {})
                        .padding(.top, reader.safeAreaInsets.top)
                        //                            .glassEffect()

                        Spacer()
                    }
                    .ignoresSafeArea(edges: .top)
                }
            }
        }
    }
}

#Preview {
    ConversationViewTest()
}
