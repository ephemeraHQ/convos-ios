import SwiftUI

struct ConversationsView: View {
    let session: any SessionManagerProtocol
    @Namespace var namespace: Namespace.ID
    @State var isPresentingComposer: Bool = false

    var body: some View {
        ConversationsListView(session: session, onSignOut: {})
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
            .background(.colorBackgroundPrimary)
            .sheet(isPresented: $isPresentingComposer) {
                EmptyView()
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
    ConversationsView(session: convos.session)
}
