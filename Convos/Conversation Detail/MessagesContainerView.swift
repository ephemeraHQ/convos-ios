import SwiftUI

struct MessagesContainerView<Content: View>: View {
    @ViewBuilder let content: () -> Content

    @State var text: String = ""

    var body: some View {
        VStack(spacing: 0) {
            MessagesToolbarView(viewModel: .init())
            content()
            MessagesInputBarView()
        }
    }
}

#Preview {
    let convos = ConvosClient.mock()
    let conversationId: String = "1"
    NavigationStack {
        MessagesContainerView {
            MessagesView(
                messagesRepository: convos.messaging.messagesRepository(
                    for: conversationId
                )
            )
        }
    }
}
