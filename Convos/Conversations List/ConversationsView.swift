import SwiftUI

struct ConversationsView: View {
    let session: any SessionManagerProtocol
    @State var viewModel: ConversationsViewModel

    @Namespace private var namespace: Namespace.ID
    @State private var presentingExplodeConfirmation: Bool = false
    @Environment(\.dismiss) private var dismiss: DismissAction

    init(
        session: any SessionManagerProtocol
    ) {
        self.session = session
        let conversationsRepository = session.conversationsRepository(
            for: .allowed
        )
        let conversationsCountRepository = session.conversationsCountRepo(
            for: .all,
            kinds: .groups
        )
        self.viewModel = ConversationsViewModel(
            session: session,
            conversationsRepository: conversationsRepository,
            conversationsCountRepository: conversationsCountRepository
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.unpinnedConversations.isEmpty {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ConversationsListEmptyCTA(
                                onStartConvo: viewModel.onStartConvo,
                                onJoinConvo: viewModel.onJoinConvo
                            )
                            .padding(DesignConstants.Spacing.step6x)
                        }
                    }
                } else {
                    List(viewModel.unpinnedConversations, id: \.self, selection: $viewModel.selectedConversation) { conversation in
                        ZStack {
                            ConversationsListItem(conversation: conversation)
                            let conversationViewModel = viewModel.conversationViewModel(for: conversation)
                            NavigationLink(value: conversationViewModel) {
                                EmptyView()
                            }
                            .opacity(0.0) // zstack hides disclosure indicator
                        }
                        .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
                        .listRowSeparator(.hidden)
                    }
                    .listStyle(.plain)
                    .navigationDestination(item: $viewModel.selectedConversation) { conversationViewModel in
                        ConversationView(viewModel: conversationViewModel)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        presentingExplodeConfirmation = true
                    } label: {
                        HStack(spacing: DesignConstants.Spacing.step2x) {
                            Circle()
                                .fill(.colorOrange)
                                .frame(width: 24.0, height: 24.0)

                            Text("Convos")
                                .font(.system(size: 16.0, weight: .medium))
                                .foregroundStyle(.colorTextPrimary)
                        }
                        .padding(10)
                    }
                    .glassEffect(.regular.interactive())
                    .confirmationDialog("", isPresented: $presentingExplodeConfirmation) {
                        Button("Explode", role: .destructive) {
                            do {
                                try session.deleteAllAccounts()
                            } catch {
                                Logger.error("Error deleting all accounts: \(error)")
                            }
                        }

                        Button("Cancel") {
                            presentingExplodeConfirmation = false
                        }
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Filter", systemImage: "line.3.horizontal.decrease") {
                        //
                    }
                    .disabled(true)
                }

                ToolbarItem(placement: .bottomBar) {
                    Spacer()
                }

                ToolbarItem(placement: .bottomBar) {
                    Button("Compose", systemImage: "plus") {
                        viewModel.onStartConvo()
                    }
                }
                .matchedTransitionSource(
                    id: "composer-transition-source",
                    in: namespace
                )
            }
            .fullScreenCover(item: $viewModel.newConversationViewModel) { viewModel in
                NewConversationView(viewModel: viewModel)
                    .background(.white)
                    .interactiveDismissDisabled()
                    .navigationTransition(
                        .zoom(
                            sourceID: "composer-transition-source",
                            in: namespace
                        )
                    )
            }
        }
        .background(.colorBackgroundPrimary)
    }
}

#Preview {
    let convos = ConvosClient.mock()
    ConversationsView(
        session: convos.session
    )
}
