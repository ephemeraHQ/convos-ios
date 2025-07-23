import Foundation
import SwiftUI

struct ConversationsListEmptyCTA: View {
    let onStartConvo: () -> Void
    let onJoinConvo: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: DesignConstants.Spacing.step4x) {
            Text("Pop-up private conversations")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(.colorTextPrimary)
            Text("Chat instantly, with anybody.\nNo accounts. New you every time.")
                .font(.body)
                .foregroundStyle(.colorTextSecondary)
            HStack {
                Button {
                    onStartConvo()
                } label: {
                    Text("Start a convo")
                        .font(.body)
                }
                .convosButtonStyle(.rounded(fullWidth: false))
                Button {
                    onJoinConvo()
                } label: {
                    Text("or join one")
                }
                .convosButtonStyle(.text)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.colorFillMinimal)
        .cornerRadius(32.0)
    }
}

struct ConversationsListView: View {
    private let session: any SessionManagerProtocol
    @Binding var isPresentingComposer: Bool
    @Binding var path: [ConversationsRoute]
    @State var viewModel: ConversationsListViewModel

    init(session: any SessionManagerProtocol,
         isPresentingComposer: Binding<Bool>,
         path: Binding<[ConversationsRoute]>) {
        self.session = session
        _isPresentingComposer = isPresentingComposer
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
                if viewModel.unpinnedConversations.isEmpty {
                    ConversationsListEmptyCTA {
                        isPresentingComposer = true
                    } onJoinConvo: {
                        isPresentingComposer = true
                    }
                    .padding(DesignConstants.Spacing.step6x)
                } else {
                    ForEach(viewModel.unpinnedConversations) { conversation in
                        NavigationLink(value: ConversationsRoute.conversation(dependencies(for: conversation))) {
                            ConversationsListItem(conversation: conversation)
                        }
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
            myProfileWriter: messagingService.myProfileWriter(),
            myProfileRepository: messagingService.myProfileRepository(),
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
    @Previewable @State var isPresentingComposer: Bool = false
    @Previewable @State var path: [ConversationsRoute] = []
    let convos = ConvosClient.mock()

    ConversationsListView(
        session: convos.session,
        isPresentingComposer: $isPresentingComposer,
        path: $path
    )
}

#Preview {
    ConversationsListEmptyCTA {
    } onJoinConvo: {
    }
}
