import ConvosCore
import SwiftUI

struct ConversationsView: View {
    let session: any SessionManagerProtocol
    @State var viewModel: ConversationsViewModel

    @Namespace private var namespace: Namespace.ID
    @State private var presentingDebugView: Bool = false
    @State private var presentingAppSettings: Bool = false
    @Environment(\.dismiss) private var dismiss: DismissAction

    @FocusState private var focusState: MessagesViewInputFocus?
    @State private var sidebarWidth: CGFloat = 0.0
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass: UserInterfaceSizeClass?

    init(
        session: any SessionManagerProtocol
    ) {
        self.session = session
        self.viewModel = ConversationsViewModel(session: session)
    }

    var emptyConversationsViewScrollable: some View {
        ScrollView {
            LazyVStack(spacing: 0.0) {
                emptyConversationsView
            }
        }
    }

    var emptyConversationsView: some View {
        ConversationsListEmptyCTA(
            onStartConvo: viewModel.onStartConvo,
            onJoinConvo: viewModel.onJoinConvo
        )
    }

    var hasEarlyAccessView: some View {
        ConversationInfoPresenter(
            viewModel: viewModel.selectedConversationViewModel,
            focusState: $focusState,
            sidebarColumnWidth: $sidebarWidth,
        ) {
            NavigationSplitView {
                Group {
                    if viewModel.unpinnedConversations.isEmpty && horizontalSizeClass == .compact {
                        emptyConversationsViewScrollable
                    } else {
                        List(viewModel.unpinnedConversations, id: \.self, selection: $viewModel.selectedConversation) { conversation in
                            if viewModel.unpinnedConversations.first == conversation,
                               viewModel.unpinnedConversations.count == 1 && !viewModel.hasCreatedMoreThanOneConvo &&
                                horizontalSizeClass == .compact {
                                emptyConversationsView
                                    .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
                                    .listRowSeparator(.hidden)
                            }

                            ConversationsListItem(conversation: conversation)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        viewModel.leave(conversation: conversation)
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                }
                                .listRowSeparator(.hidden)
                                .listRowBackground(
                                    RoundedRectangle(cornerRadius: DesignConstants.CornerRadius.mediumLarge)
                                        .fill(
                                            conversation == viewModel.selectedConversation ? .colorFillMinimal : .clear
                                        )
                                        .padding(.horizontal, DesignConstants.Spacing.step3x)
                                )
                                .listRowInsets(
                                    .init(
                                        top: 0,
                                        leading: 0,
                                        bottom: 0,
                                        trailing: 0
                                    )
                                )
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
                    emptyConversationsViewScrollable
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
        .selfSizingSheet(isPresented: $viewModel.presentingExplodeInfo) {
            ExplodeInfoView()
        }
        .selfSizingSheet(isPresented: $viewModel.presentingEarlyAccessInfo) {
            EarlyAccessInfoView()
        }
        .selfSizingSheet(isPresented: $viewModel.presentingMaxNumberOfConvosReachedInfo) {
            MaxedOutInfoView(maxNumberOfConvos: viewModel.maxNumberOfConvos)
        }
        .onAppear {
            viewModel.onAppear()
        }
    }

    var body: some View {
        Group {
            if !viewModel.hasEarlyAccess,
               let joinViewModel = viewModel.newConversationViewModel {
                NewConversationView(viewModel: joinViewModel)
            } else {
                hasEarlyAccessView
            }
        }
        .onOpenURL { url in
            viewModel.handleURL(url)
        }
    }
}

#Preview {
    let convos = ConvosClient.mock()
    ConversationsView(
        session: convos.session
    )
}
