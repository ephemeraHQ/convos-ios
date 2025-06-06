import Foundation
import SwiftUI

struct ConversationsListView: View {
    enum Route: Hashable {
        case composer, securityLine, conversation(Conversation)
    }

    @Environment(MessagingServiceObservable.self)
    private var messagingService: MessagingServiceObservable

    let convos: ConvosClient
    var userState: UserState
    var conversationsState: ConversationsState
    @State private var path: [Route] = []

    init(convos: ConvosClient,
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
                        if !conversationsState.securityLineConversations.isEmpty {
                            NavigationLink(value: Route.securityLine) {
                                SecurityLineListItem(count: conversationsState.securityLineConversations.count)
                            }
                        }

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
                                messagingService: messagingService.messagingService,
                                draftConversationComposer: messagingService
                                    .messagingService
                                    .draftConversationComposer()
                            )
                            .ignoresSafeArea()
                            .toolbarVisibility(.hidden, for: .navigationBar)
                        case .securityLine:
                            SecurityLineView(
                                path: $path,
                                conversationsState: conversationsState
                            )
                            .toolbarVisibility(.hidden, for: .navigationBar)
                        case .conversation(let conversation):
                            let conversationRepository = convos.messaging.conversationRepository(
                                for: conversation.id
                            )
                            let messagesRepository = convos.messaging.messagesRepository(
                                for: conversation.id
                            )
                            let messageWriter = convos.messaging.messageWriter(
                                for: conversation.id
                            )
                            let consentWriter = convos.messaging.conversationConsentWriter()
                            ConversationView(
                                conversationRepository: conversationRepository,
                                messagesRepository: messagesRepository,
                                outgoingMessageWriter: messageWriter,
                                conversationConsentWriter: consentWriter
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
    let convos = ConvosClient.mock()
    let messagingService = MessagingServiceObservable(messagingService: convos.messaging)
    let userRepository = convos.messaging.userRepository()
    let conversationsRepository = convos.messaging.conversationsRepository()

    ConversationsListView(
        convos: convos,
        userRepository: userRepository,
        conversationsRepository: conversationsRepository
    )
    .environment(messagingService)
}
