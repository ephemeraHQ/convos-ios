import SwiftUI

struct ContactCardsView: View {
    let session: any SessionManagerProtocol
    @Namespace private var namespace: Namespace.ID
    @State private var state: ContactCardsState
    @State private var isPresentingConversationsSheet: Bool = false

    init(
        session: any SessionManagerProtocol
    ) {
        self.session = session
        _state = State(initialValue: .init(inboxesRepository: session.inboxesRepository))
    }

    // MARK: -

    var body: some View {
        NavigationStack {
            GeometryReader { reader in
                ScrollView {
                    LazyVStack(spacing: -(reader.size.width - DesignConstants.Spacing.step8x)) {
                        ForEach(state.contactCards, id: \.self) { contactCard in
                            ContactCardView(contactCard: contactCard)
                        }
                    }
                    .padding(.vertical, DesignConstants.Spacing.step4x)
                    .padding(.horizontal, DesignConstants.Spacing.step4x)
                }
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
            .background(.colorFillMinimal)
        }
        .fullScreenCover(isPresented: $isPresentingConversationsSheet) {
            ConversationsView(session: session)
                .navigationTransition(
                    .zoom(
                        sourceID: "conversations-transition-source",
                        in: namespace
                    )
                )
        }
        .background(.colorFillMinimal)
    }
}

#Preview {
    let convos = ConvosClient.mock()
    ContactCardsView(session: convos.session)
}
