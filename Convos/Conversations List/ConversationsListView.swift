import Foundation
import SwiftUI

struct ConversationsListView: View {
    enum Route: Hashable {
        case composer(AnyDraftConversationComposer),
             securityLine,
             conversation(Conversation)
    }

    private let session: any SessionManagerProtocol
    @State var viewModel: ConversationsListViewModel
    let onSignOut: () -> Void

    @Environment(\.dismiss) private var dismissAction: DismissAction
    @State private var path: [Route] = []

    init(session: any SessionManagerProtocol,
         onSignOut: @escaping () -> Void) {
        self.session = session
        let conversationsRepository = session.conversationsRepository(for: .allowed)
        let securityLineConversationsCountRepo = session.conversationsCountRepo(for: .securityLine)
        self.viewModel = .init(
            conversationsRepository: conversationsRepository,
            securityLineConversationsCountRepo: securityLineConversationsCountRepo
        )
        self.onSignOut = onSignOut
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(spacing: 0) {
                    if viewModel.securityLineConversationsCount != 0 {
                        NavigationLink(value: Route.securityLine) {
                            SecurityLineListItem(count: viewModel.securityLineConversationsCount)
                        }
                    }

                    ForEach(viewModel.unpinnedConversations) { conversation in
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
                            conversationLocalStateWriter: localStateWriter
                        )
                        .ignoresSafeArea()
                    }
                }
            }
            .navigationTitle("Convos")
            .toolbarTitleDisplayMode(.inlineLarge)
        }
    }
}

#Preview {
    let convos = ConvosClient.mock()

    ConversationsListView(
        session: convos.session,
        onSignOut: {}
    )
}
