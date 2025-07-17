import Foundation
import SwiftUI

struct ConversationsListView: View {
    private let session: any SessionManagerProtocol
    @Binding var path: [ConversationsRoute]
    @State var viewModel: ConversationsListViewModel

    init(session: any SessionManagerProtocol,
         path: Binding<[ConversationsRoute]>) {
        self.session = session
        _path = path
        let conversationsRepository = session.conversationsRepository(for: .allowed)
        let securityLineConversationsCountRepo = session.conversationsCountRepo(for: .securityLine)
        self.viewModel = .init(
            conversationsRepository: conversationsRepository,
            securityLineConversationsCountRepo: securityLineConversationsCountRepo
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.unpinnedConversations) { conversation in
                    NavigationLink(value: ConversationsRoute.conversation(dependencies(for: conversation))) {
                        ConversationsListItem(conversation: conversation)
                    }
                }
            }
            .navigationDestination(for: ConversationsRoute.self) { route in
                switch route {
                case .conversation(let conversationDetail):
                    ConversationView(dependencies: conversationDetail)
                        .ignoresSafeArea()
                }
            }
        }
    }

    private func dependencies(for conversation: Conversation) -> ConversationViewDependencies {
        let messagingService = session.messagingService(for: conversation.inboxId)
        return .init(
            conversationId: conversation.id,
            conversationRepository: messagingService.conversationRepository(for: conversation.id),
            messagesRepository: messagingService.messagesRepository(for: conversation.id),
            outgoingMessageWriter: messagingService.messageWriter(for: conversation.id),
            conversationConsentWriter: messagingService.conversationConsentWriter(),
            conversationLocalStateWriter: messagingService.conversationLocalStateWriter(),
            groupMetadataWriter: messagingService.groupMetadataWriter()
        )
    }
}

#Preview {
    @Previewable @State var path: [ConversationsRoute] = []
    let convos = ConvosClient.mock()

    ConversationsListView(
        session: convos.session,
        path: $path
    )
}
