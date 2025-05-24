import Foundation
import SwiftUI

struct ConversationsListView: View {
    enum Route: Hashable {
        case composer, conversation(Conversation)
    }

    @Environment(MessagingServiceObservable.self)
    private var messagingService: MessagingServiceObservable

    let convos: ConvosSDK.ConvosClient
    var userState: UserState
    var conversationsState: ConversationsState
    @State private var path: [Route] = []

    init(convos: ConvosSDK.ConvosClient,
         userRepository: any UserRepositoryProtocol,
         conversationsRepository: any ConversationsRepositoryProtocol) {
        self.convos = convos
        self.userState = .init(userRepository: userRepository)
        self.conversationsState = .init(conversationsRepository: conversationsRepository)
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                ConversationsListNavigationBar(
                    userState: userState,
                    isComposeEnabled: messagingService.canStartConversation,
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
                                messagesRepository: convos.messaging.messagesRepository(
                                    for: "draft"
                                ) // TODO: better way
                            )
                            .ignoresSafeArea()
                            .toolbarVisibility(.hidden, for: .navigationBar)
                        case .conversation(let conversation):
                            let conversationRepository = MockConversationRepository()
                            let messageWriter = convos.messaging.messageWriter(
                                for: conversation.id
                            )
                            let messagesRepository = convos.messaging.messagesRepository(
                                for: conversation.id
                            )
                            MessagesView(
                                conversationRepository: conversationRepository,
                                messageWriter: messageWriter,
                                messagesRepository: messagesRepository
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
    @Previewable @State var messagingService: MessagingServiceObservable = .init(
        messagingService: MockMessagingService()
    )
    ConversationsListView(convos: .mock(),
                          userRepository: userRepository,
                          conversationsRepository: conversationsRepository)
    .environment(messagingService)
}
