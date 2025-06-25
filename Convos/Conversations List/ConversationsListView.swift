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
                if viewModel.securityLineConversationsCount != 0 {
                    NavigationLink(value: ConversationsRoute.securityLine) {
                        SecurityLineListItem(count: viewModel.securityLineConversationsCount)
                    }
                }

                ForEach(viewModel.unpinnedConversations) { conversation in
                    NavigationLink(value: ConversationsRoute.conversation(conversation)) {
                        ConversationsListItem(conversation: conversation)
                    }
                }
            }
            .navigationDestination(for: ConversationsRoute.self) { route in
                switch route {
                case .securityLine:
                    SecurityLineView(
                        session: session,
                        path: $path
                    )
                case .conversation(let conversation):
                    let messagingService = session.messagingService(for: conversation.inboxId)
                    let conversationRepository = messagingService.conversationRepository(
                        for: conversation.id
                    )
                    let messagesRepository = messagingService.messagesRepository(
                        for: conversation.id
                    )
                    let messageWriter = messagingService.messageWriter(
                        for: conversation.id
                    )
                    let consentWriter = messagingService.conversationConsentWriter()
                    let localStateWriter = messagingService.conversationLocalStateWriter()
                    ConversationView(
                        conversationRepository: conversationRepository,
                        messagesRepository: messagesRepository,
                        outgoingMessageWriter: messageWriter,
                        conversationConsentWriter: consentWriter,
                        conversationLocalStateWriter: localStateWriter,
                        groupMetadataWriter: messagingService.groupMetadataWriter()
                    )
                    .ignoresSafeArea()
                }
            }
        }
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
