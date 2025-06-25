import SwiftUI

enum ConversationsRoute: Hashable {
    case securityLine,
         conversation(Conversation)
}

struct ConversationsView: View {
    let session: any SessionManagerProtocol
    @Namespace var namespace: Namespace.ID
    @State var isPresentingComposer: Bool = false
    @State var path: [ConversationsRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            ConversationsListView(session: session, path: $path)
                .navigationTitle("Convos")
                .toolbarTitleDisplayMode(.inlineLarge)
                .toolbar {
                    ToolbarItem(placement: .bottomBar) {
                        Button("Filter", systemImage: "line.3.horizontal.decrease") {
                            //
                        }
                    }
                    ToolbarItem(placement: .bottomBar) {
                        Spacer()
                    }
                    ToolbarItem(placement: .bottomBar) {
                        Button("Compose", systemImage: "square.and.pencil") {
                            isPresentingComposer = true
                        }
                    }
                    .matchedTransitionSource(
                        id: "composer-transition-source",
                        in: namespace
                    )
                }
        }
        .background(.colorBackgroundPrimary)
        .sheet(isPresented: $isPresentingComposer) {
            ConversationComposerView(
                session: session
            )
            .navigationTransition(
                .zoom(
                    sourceID: "composer-transition-source",
                    in: namespace
                )
            )
        }
        .interactiveDismissDisabled(!path.isEmpty)
    }
}

#Preview {
    @Previewable @State var path: [ConversationsRoute] = []
    let convos = ConvosClient.mock()
    ConversationsView(
        session: convos.session
    )
}
