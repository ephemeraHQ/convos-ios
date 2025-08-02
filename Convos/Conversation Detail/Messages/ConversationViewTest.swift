import SwiftUI

struct ConversationViewTest: View {
    let conversationId: String = "1"
    static var messaging: any MessagingServiceProtocol = MockMessagingService()
    let messagesRepository: any MessagesRepositoryProtocol = Self.messaging.messagesRepository(for: "1")
    let inviteRepository: any InviteRepositoryProtocol = Self.messaging.inviteRepository(for: "1")

    @State private var inputViewHeight: CGFloat = 0.0 {
        didSet {
            Logger.info("Input view height: \(inputViewHeight)")
        }
    }

    var body: some View {
        GeometryReader { reader in
            NavigationStack {
                ZStack {
                    Group {
                        MessagesView(
                            messagesRepository: messagesRepository,
                            inviteRepository: inviteRepository
                        )
                        .ignoresSafeArea()
                    }
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

                    VStack {
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .safeAreaBar(edge: .bottom) {
                        MessagesInputView(
                            viewModel: .init(myProfileWriter: MockMyProfileWriter(), outgoingMessageWriter: MockOutgoingMessageWriter()),
                            conversationState: .init(
                                myProfileRepository: MockMessagingService().myProfileRepository(),
                                conversationRepository: MockConversationRepository()
                            )
                        )
                        .background(HeightReader())
                        .onPreferenceChange(HeightPreferenceKey.self) { height in
                            inputViewHeight = height
                        }
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
