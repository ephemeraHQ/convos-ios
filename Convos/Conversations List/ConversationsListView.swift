import Foundation
import SwiftUI

struct ConversationsListView: View {
    private let session: any SessionManagerProtocol
    let onNewConversation: () -> Void
    let onJoinConversation: () -> Void
    @Binding var path: [ConversationsRoute]
    @State var viewModel: ConversationsListViewModel

    init(session: any SessionManagerProtocol,
         onNewConversation: @escaping () -> Void,
         onJoinConversation: @escaping () -> Void,
         path: Binding<[ConversationsRoute]>) {
        self.session = session
        self.onNewConversation = onNewConversation
        self.onJoinConversation = onJoinConversation
        _path = path
        let conversationsRepository = session.conversationsRepository(for: .allowed)
        self.viewModel = .init(
            session: session,
            conversationsRepository: conversationsRepository,
            conversationsCountRepository: session.conversationsCountRepo(
                for: .all,
                kinds: .groups
            )
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if viewModel.unpinnedConversations.isEmpty {
                    ConversationsListEmptyCTA(
                        onStartConvo: onNewConversation,
                        onJoinConvo: onJoinConversation
                    )
                    .padding(DesignConstants.Spacing.step6x)
                } else {
                    ForEach(viewModel.unpinnedConversations) { conversation in
                        NavigationLink(value: ConversationsRoute.conversation(conversation)) {
                            ConversationsListItem(conversation: conversation)
                        }
                    }
                }
            }
        }
        .navigationDestination(for: ConversationsRoute.self) { route in
            switch route {
            case .conversation(let conversation):
                ConversationView(viewModel: viewModel.viewModel(for: conversation))
            }
        }
    }
}

#Preview {
    @Previewable @State var path: [ConversationsRoute] = []
    let convos = ConvosClient.mock()

    ConversationsListView(
        session: convos.session,
        onNewConversation: {},
        onJoinConversation: {},
        path: $path
    )
}
