import SwiftUI

enum ConversationsRoute: Hashable {
    case conversation(ConversationViewDependencies)
}

struct ConversationDetail {
    let conversation: Conversation
    let messagingService: AnyMessagingService
}

struct ConversationsView: View {
    let session: any SessionManagerProtocol
    @Namespace var namespace: Namespace.ID
    @State var isPresentingComposer: Bool = false
    @State var isPresentingJoinConversation: Bool = false
    @State var presentingExplodeConfirmation: Bool = false
    @State var path: [ConversationsRoute] = []
    @Environment(\.dismiss) var dismiss: DismissAction

    var body: some View {
        NavigationStack(path: $path) {
            ConversationsListView(
                session: session,
                isPresentingComposer: $isPresentingComposer,
                isPresentingJoinConversation: $isPresentingJoinConversation,
                path: $path
            )
            .toolbarTitleDisplayMode(.inlineLarge)
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
                    .glassEffect(.clear.tint(.white))
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
                        isPresentingComposer = true
                    }
                }
                .matchedTransitionSource(
                    id: "composer-transition-source",
                    in: namespace
                )
            }
            .fullScreenCover(isPresented: $isPresentingJoinConversation) {
                NewConversationView(session: session, presentingJoinConversation: true)
                    .ignoresSafeArea()
                    .background(.white)
                    .interactiveDismissDisabled()
            }
            .fullScreenCover(isPresented: $isPresentingComposer) {
                NewConversationView(session: session, presentingJoinConversation: false)
                    .ignoresSafeArea()
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
    @Previewable @State var path: [ConversationsRoute] = []
    let convos = ConvosClient.mock()
    ConversationsView(
        session: convos.session
    )
}
