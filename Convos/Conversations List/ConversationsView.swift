import ConvosCore
import SwiftUI

struct ConversationsView: View {
    let session: any SessionManagerProtocol
    @Bindable var viewModel: ConversationsViewModel
    @State private var deepLinkHandler: DeepLinkHandler = DeepLinkHandler()

    @Namespace private var namespace: Namespace.ID
    @State private var presentingExplodeConfirmation: Bool = false
    @State private var presentingDebugView: Bool = false
    @State private var presentingAppSettings: Bool = false
    @Environment(\.dismiss) private var dismiss: DismissAction

    @FocusState private var focusState: MessagesViewInputFocus?
    @State private var sidebarWidth: CGFloat = 0.0
    @State private var infoSheetHeight: CGFloat = 0.0
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass: UserInterfaceSizeClass?

    init(
        session: any SessionManagerProtocol
    ) {
        self.session = session
        let conversationsRepository = session.conversationsRepository(
            for: .allowed
        )
        let conversationsCountRepository = session.conversationsCountRepo(
            for: .allowed,
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
            viewModel: viewModel.selectedConversationViewModel,
            focusState: $focusState,
            sidebarColumnWidth: $sidebarWidth,
        ) {
            NavigationSplitView {
                Group {
                    if viewModel.unpinnedConversations.isEmpty && horizontalSizeClass == .compact {
                        emptyConversationsView
                    } else {
                        List(viewModel.unpinnedConversations, id: \.self, selection: $viewModel.selectedConversation) { conversation in
                            ConversationsListItem(conversation: conversation)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    viewModel.leave(conversation: conversation)
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
                        ConvosToolbarButton(padding: false) {
                            presentingAppSettings = true
                        }
                    }
                    .matchedTransitionSource(
                        id: "app-settings-transition-source",
                        in: namespace
                    )

                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Filter", systemImage: "line.3.horizontal.decrease") {
                            //
                        }
                        .disabled(true)
                    }
                    .matchedTransitionSource(
                        id: "filter-view-transition-source",
                        in: namespace
                    )

                    ToolbarItem(placement: .bottomBar) {
                        Spacer()
                    }

                    ToolbarItem(placement: .bottomBar) {
                        Button("Scan", systemImage: "qrcode.viewfinder") {
                            viewModel.onJoinConvo()
                        }
                    }
                    .matchedTransitionSource(
                        id: "composer-transition-source",
                        in: namespace
                    )

                    ToolbarItem(placement: .bottomBar) {
                        Button("Compose", systemImage: "square.and.pencil") {
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
                if let conversationViewModel = viewModel.selectedConversationViewModel {
                    ConversationView(
                        viewModel: conversationViewModel,
                        focusState: $focusState,
                        onScanInviteCode: {},
                        onDeleteConversation: {},
                        confirmDeletionBeforeDismissal: false,
                        messagesTopBarTrailingItem: .share
                    )
                } else if horizontalSizeClass != .compact {
                    emptyConversationsView
                } else {
                    EmptyView()
                }
            }
        }
        .sheet(isPresented: $presentingAppSettings) {
            AppSettingsView(onDeleteAllInboxes: viewModel.deleteAllInboxes)
                .navigationTransition(
                    .zoom(
                        sourceID: "app-settings-transition-source",
                        in: namespace
                    )
                )
        }
        .fullScreenCover(item: $viewModel.newConversationViewModel) { viewModel in
            NewConversationView(viewModel: viewModel)
                .background(.colorBackgroundPrimary)
                .interactiveDismissDisabled()
                .navigationTransition(
                    .zoom(
                        sourceID: "composer-transition-source",
                        in: namespace
                    )
                )
        }
        .sheet(isPresented: $viewModel.presentingExplodeInfo) {
            ExplodeInfoView()
                .fixedSize(horizontal: false, vertical: true)
                .readHeight { sheetHeight in
                    infoSheetHeight = sheetHeight
                }
                .presentationDetents([.height(infoSheetHeight)])
        }
        .sheet(isPresented: $viewModel.presentingMaxNumberOfConvosReachedInfo) {
            MaxedOutInfoView(maxNumberOfConvos: viewModel.maxNumberOfConvos)
                .fixedSize(horizontal: false, vertical: true)
                .readHeight { sheetHeight in
                    infoSheetHeight = sheetHeight
                }
                .presentationDetents([.height(infoSheetHeight)])
        }
        .onOpenURL { url in
            handleDeepLink(url)
        }
        .onChange(of: deepLinkHandler.shouldPresentRequestToJoin) { _, shouldPresent in
            if shouldPresent, let inviteCode = deepLinkHandler.inviteCodeToProcess {
                handleRequestToJoin(inviteCode)
            }
        }
    }

    private func handleDeepLink(_ url: URL) {
        _ = deepLinkHandler.handleURL(url)
    }

    private func handleRequestToJoin(_ inviteCode: String) {
        // This creates a request to join via invite code
        // For deep links, we want to directly join without showing the scanner
        // All validation (already joined, invalid codes, etc.) is handled by ConversationStateMachine
        viewModel.newConversationViewModel = NewConversationViewModel(
            session: session,
            showScannerOnAppear: false,
            delegate: viewModel,
            prefilledInviteCode: inviteCode
        )
        deepLinkHandler.clearPendingDeepLink()
    }
}

#Preview {
    let convos = ConvosClient.mock()
    ConversationsView(
        session: convos.session
    )
}
