import Foundation
import SwiftUI

struct ChatListView: View {
    let convos: ConvosSDK.Convos
    @State var userState: UserState
    @State var conversationsState: ConversationsState

    init(convos: ConvosSDK.Convos,
         userRepository: any UserRepositoryProtocol,
         conversationsRepository: any ConversationsRepositoryProtocol) {
        self.convos = convos
        _userState = State(wrappedValue: .init(userRepository: userRepository))
        _conversationsState = State(
            wrappedValue: ConversationsState(
                conversationsRepository: conversationsRepository
            )
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                VStack(spacing: 0) {
                    ChatListNavigationBar(userState: userState, signOut: {
                        Task {
                            try await convos.signOut()
                        }
                    })
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(conversationsState.unpinnedConversations) { conversation in
                                NavigationLink(value: conversation) {
                                    ChatListItem(conversation: conversation)
                                }
                            }
                        }
                        .navigationDestination(for: Conversation.self, destination: { conversation in
                            MessagesView(messagesStore: MockMessagesStore())
                                .ignoresSafeArea()
                                .toolbarVisibility(.hidden, for: .navigationBar)
                                .toolbarVisibility(.hidden, for: .navigationBar)
                        })
                    }
                }
                .navigationBarHidden(true)
            }
        }
    }
}

#Preview {
    //    ChatListView(conversationStore: CTConversationStore(), identityStore: CTIdentityStore())
}
