import Foundation
import SwiftUI

struct ConversationsListView: View {
    enum Route: Hashable {
        case composer(AnyDraftConversationComposer),
             securityLine,
             conversation(Conversation)
    }

    @Environment(\.dismiss) private var dismissAction: DismissAction
    @Environment(MessagingServiceObservable.self)
    private var messagingService: MessagingServiceObservable

    let convos: ConvosClient
    var userState: UserState
    var conversationsState: ConversationsListState
    @State private var path: [Route] = []

    init(convos: ConvosClient,
         userRepository: any UserRepositoryProtocol,
         conversationsRepository: any ConversationsRepositoryProtocol) {
        self.convos = convos
        self.userState = .init(userRepository: userRepository)
        let securityLineConversationsCountRepo = convos.messaging.conversationsCountRepo(for: .securityLine)
        self.conversationsState = .init(
            conversationsRepository: conversationsRepository,
            securityLineConversationsCountRepo: securityLineConversationsCountRepo
        )
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                ConversationsListNavigationBar(
                    userState: userState,
                    isComposeEnabled: messagingService.canStartConversation,
                    onCompose: {
                        path.append(.composer(AnyDraftConversationComposer(messagingService
                            .messagingService
                            .draftConversationComposer())))
                    },
                    onSignOut: {
                        Task {
                            do {
                                try await convos.signOut()
                            } catch {
                                Logger.error("Error signing out: \(error)")
                            }
                        }
                    }
                )
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if conversationsState.securityLineConversationsCount != 0 {
                            NavigationLink(value: Route.securityLine) {
                                SecurityLineListItem(count: conversationsState.securityLineConversationsCount)
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
                        case .composer(let draftConversationComposer):
                            ConversationComposerView(
                                draftConversationComposer: draftConversationComposer
                            )
                            .ignoresSafeArea()
                            .toolbarVisibility(.hidden, for: .navigationBar)
                        case .securityLine:
                            SecurityLineView(
                                messagingService: convos.messaging,
                                path: $path
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
                            let localStateWriter = convos.messaging.conversationLocalStateWriter()
                            ConversationView(
                                conversationRepository: conversationRepository,
                                messagesRepository: messagesRepository,
                                outgoingMessageWriter: messageWriter,
                                conversationConsentWriter: consentWriter,
                                conversationLocalStateWriter: localStateWriter
                            )
                            .ignoresSafeArea()
                            .toolbarVisibility(.hidden, for: .navigationBar)
                        }
                    }
                }
                .background(.colorBackgroundPrimary)
            }
        }
    }
}

#Preview {
    let convos = ConvosClient.mock()
    let messagingService = MessagingServiceObservable(messagingService: convos.messaging)
    let userRepository = convos.messaging.userRepository()
    let conversationsRepository = convos.messaging.conversationsRepository(for: .allowed)

    ConversationsListView(
        convos: convos,
        userRepository: userRepository,
        conversationsRepository: conversationsRepository
    )
    .environment(messagingService)
}
