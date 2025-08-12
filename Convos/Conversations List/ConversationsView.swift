import SwiftUI

struct ConversationsView: View {
    let session: any SessionManagerProtocol
    @State var viewModel: ConversationsViewModel

    @Namespace private var namespace: Namespace.ID
    @State private var presentingExplodeConfirmation: Bool = false
    @State private var presentingDebugView: Bool = false
    @Environment(\.dismiss) private var dismiss: DismissAction

    @FocusState private var focusState: MessagesViewInputFocus?
    @State private var sidebarWidth: CGFloat = 0.0
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass: UserInterfaceSizeClass?

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

    var emptyConversationsView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ConversationsListEmptyCTA(
                    onStartConvo: viewModel.onStartConvo,
                    onJoinConvo: viewModel.onJoinConvo
                )
                .padding(DesignConstants.Spacing.step6x)
            }
        }
    }

    var body: some View {
        ConversationInfoPresenter(
            viewModel: viewModel,
            focusState: $focusState,
            sidebarColumnWidth: $sidebarWidth,
        ) {
            NavigationSplitView {
                Group {
                    if viewModel.unpinnedConversations.isEmpty && horizontalSizeClass == .compact {
                        emptyConversationsView
                    } else {
                        List(viewModel.unpinnedConversations, id: \.self, selection: $viewModel.selectedConversation) { conversation in
                            let conversationViewModel = viewModel.conversationViewModel(for: conversation)
                            ZStack {
                                ConversationsListItem(conversation: conversation)
                                NavigationLink(value: conversationViewModel) {
                                    EmptyView()
                                }
                                .opacity(0.0) // zstack hides disclosure indicator
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    conversationViewModel.leaveConvo()
                                } label: {
                                    Image(systemName: "trash")
                                }
                            }
                            .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
                            .listRowSeparator(.hidden)
                        }
                        .listStyle(.plain)
                    }
                }
                .onGeometryChange(for: CGSize.self) {
                    $0.size
                } action: { newValue in
                    sidebarWidth = newValue.width
                }
                .background(.colorBackgroundPrimary)
                .toolbarTitleDisplayMode(.inline)
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
                        Button {
                            presentingDebugView = true
                        } label: {
                            Image(systemName: "ladybug.fill")
                        }
                    }
                    .matchedTransitionSource(
                        id: "debug-view-transition-source",
                        in: namespace
                    )

//                    ToolbarItem(placement: .topBarTrailing) {
//                        Button("Filter", systemImage: "line.3.horizontal.decrease") {
//                            //
//                        }
//                        .disabled(true)
//                    }

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
                .toolbar(removing: .sidebarToggle)
            } detail: {
                if let conversationViewModel = viewModel.selectedConversation {
                    ConversationView(
                        viewModel: conversationViewModel,
                        focusState: $focusState
                    )
                } else if horizontalSizeClass != .compact {
                    emptyConversationsView
                } else {
                    EmptyView()
                }
            }
        }
        .sheet(isPresented: $presentingDebugView) {
            DebugView()
                .navigationTransition(
                    .zoom(
                        sourceID: "debug-view-transition-source",
                        in: namespace
                    )
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
}

#Preview {
    let convos = ConvosClient.mock()
    ConversationsView(
        session: convos.session
    )
}
