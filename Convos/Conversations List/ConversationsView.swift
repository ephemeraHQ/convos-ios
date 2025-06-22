import SwiftUI

struct ConversationsView: View {
    var body: some View {
        ConversationsListView(session: MockInboxesService(), onSignOut: {})
    }
}

#Preview {
    ConversationsView()
}
