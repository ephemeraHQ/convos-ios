import SwiftUI

struct ConversationsView: View {
    let session: any SessionManagerProtocol

    var body: some View {
        ConversationsListView(session: session, onSignOut: {})
            .background(.colorBackgroundPrimary)
    }
}

#Preview {
    let convos = ConvosClient.mock()
    ConversationsView(session: convos.session)
}
