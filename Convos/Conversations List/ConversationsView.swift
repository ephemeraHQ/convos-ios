import SwiftUI

struct ConversationsView: View {
    let session: any SessionManagerProtocol

    var body: some View {
        ConversationsListView(session: session, onSignOut: {})
    }
}

//#Preview {
//    ConversationsView(session: )
//}
