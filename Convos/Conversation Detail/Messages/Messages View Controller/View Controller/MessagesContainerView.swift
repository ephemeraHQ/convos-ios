import Observation
import SwiftUI

struct MessagesContainerView<Content: View>: UIViewControllerRepresentable {
    let conversationState: ConversationState
    let outgoingMessageWriter: any OutgoingMessageWriterProtocol
    let conversationLocalStateWriter: any ConversationLocalStateWriterProtocol
    @ViewBuilder let content: () -> Content

    @State private var inputViewModel: MessagesInputViewModel

    @Environment(\.dismiss) private var dismiss: DismissAction

    init(
        conversationState: ConversationState,
        myProfileWriter: any MyProfileWriterProtocol,
        outgoingMessageWriter: any OutgoingMessageWriterProtocol,
        conversationLocalStateWriter: any ConversationLocalStateWriterProtocol,
        content: @escaping () -> Content,
    ) {
        self.conversationState = conversationState
        self.outgoingMessageWriter = outgoingMessageWriter
        self.conversationLocalStateWriter = conversationLocalStateWriter
        self.content = content
        _inputViewModel = State(initialValue: .init(
            myProfileWriter: myProfileWriter,
            outgoingMessageWriter: outgoingMessageWriter
        ))
    }

    func makeUIViewController(context: Context) -> MessagesContainerViewController {
        let viewController = MessagesContainerViewController(
            conversationState: conversationState,
            messagesInputViewModel: inputViewModel,
            outgoingMessageWriter: outgoingMessageWriter,
            conversationLocalStateWriter: conversationLocalStateWriter,
            dismissAction: context.environment.dismiss
        )

        let hostingController = UIHostingController(
            rootView: content()
        )

        viewController.embedContentController(hostingController)
        return viewController
    }

    func updateUIViewController(_ uiViewController: MessagesContainerViewController, context: Context) {
    }
}
