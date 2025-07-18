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
    @State var path: [ConversationsRoute] = []
    @Environment(\.dismiss) var dismiss: DismissAction

    var body: some View {
        NavigationStack(path: $path) {
            ConversationsListView(session: session, path: $path)
                .toolbarTitleDisplayMode(.inlineLarge)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            //
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
                            .shadow(color: .black.opacity(0.08), radius: 20, x: 0, y: 8)
                        }
                        .glassEffect(.clear.tint(.white))
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
                .fullScreenCover(isPresented: $isPresentingComposer) {
                    NavigationStack {
                        ConversationView(dependencies: .mock())
                            .ignoresSafeArea()
                            .toolbar {
                                ToolbarItem(placement: .topBarLeading) {
                                    Button(role: .cancel) {
                                        isPresentingComposer = false
                                    }
                                }
                            }
                    }
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
