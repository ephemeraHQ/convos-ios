import Foundation
import SwiftUI

struct ConversationsListView: View {
    enum Route: Hashable {
        case composer, conversation(Conversation)
    }

    let convos: ConvosSDK.ConvosClient
    @State var userState: UserState
    @State var conversationsState: ConversationsState
    @State private var path: [Route] = []

    init(convos: ConvosSDK.ConvosClient,
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
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                ConversationsListNavigationBar(
                    userState: userState,
                    onCompose: {
                        path.append(.composer)
                    },
                    onSignOut: {
                        Task {
                            try await convos.signOut()
                        }
                    }
                )
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(conversationsState.unpinnedConversations) { conversation in
                            NavigationLink(value: Route.conversation(conversation)) {
                                ConversationsListItem(conversation: conversation)
                            }
                        }
                    }
                    .navigationDestination(for: Route.self) { route in
                        switch route {
                        case .composer:
                            ConversationComposerView(
                                draftConversationRepository: MockDraftConversationRepository(),
                                messagingService: convos.messaging,
                                messagesStore: MockMessagesStore()
                            )
                            .ignoresSafeArea()
                            .toolbarVisibility(.hidden, for: .navigationBar)
                        case .conversation:
                            MessagesView(
                                conversationRepository: MockConversationRepository(),
                                messagesStore: MockMessagesStore()
                            )
                            .ignoresSafeArea()
                            .toolbarVisibility(.hidden, for: .navigationBar)
                        }
                    }
                }
                .navigationBarHidden(true)
            }
        }
    }
}

#Preview {
    @Previewable @State var userRepository = MockUserRepository()
    @Previewable @State var conversationsRepository = MockConversationsRepository()
    ConversationsListView(convos: .sdk(authService: MockAuthService()),
                          userRepository: userRepository,
                          conversationsRepository: conversationsRepository)
}
