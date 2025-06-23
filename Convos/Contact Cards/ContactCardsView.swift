import SwiftUI

struct ContactCardsView: View {
    let session: any SessionManagerProtocol
    @Namespace private var namespace: Namespace.ID
    @State private var isPresentingConversationsSheet: Bool = false

    var body: some View {
        NavigationStack {
            VStack {
            }
            .navigationTitle("Cards")
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add Card", systemImage: "plus") {
                    }
                }

                ToolbarItem(placement: .bottomBar) {
                    Spacer()
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("Chat", systemImage: "message.fill") {
                        isPresentingConversationsSheet = true
                    }
                }
                .matchedTransitionSource(
                    id: "conversations-transition-source",
                    in: namespace
                )
            }
        }
        .sheet(isPresented: $isPresentingConversationsSheet) {
            ConversationsView(session: session)
                .navigationTransition(
                    .zoom(
                        sourceID: "conversations-transition-source",
                        in: namespace
                    )
                )
        }
    }
}

//#Preview {
//    ContactCardsView()
//}
