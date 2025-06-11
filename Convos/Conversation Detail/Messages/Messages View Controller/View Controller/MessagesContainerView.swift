import SwiftUI

struct MessagesContainerView<Content: View>: UIViewControllerRepresentable {
    let conversationState: ConversationState
    let outgoingMessageWriter: any OutgoingMessageWriterProtocol
    let conversationConsentWriter: any ConversationConsentWriterProtocol
    let conversationLocalStateWriter: any ConversationLocalStateWriterProtocol
    @ViewBuilder let content: (Binding<String>, Binding<Bool>) -> Content

    @State private var text: String = ""
    @State private var sendButtonEnabled: Bool = false

    func makeUIViewController(context: Context) -> MessagesContainerViewController {
        let viewController = MessagesContainerViewController(
            conversationState: conversationState,
            outgoingMessageWriter: outgoingMessageWriter,
            conversationConsentWriter: conversationConsentWriter,
            conversationLocalStateWriter: conversationLocalStateWriter,
            dismissAction: context.environment.dismiss,
            textBinding: $text,
            sendButtonEnabled: $sendButtonEnabled
        )

        let hostingController = UIHostingController(
            rootView: content($text, $sendButtonEnabled)
        )

        viewController.embedContentController(hostingController)
        return viewController
    }

    func updateUIViewController(_ uiViewController: MessagesContainerViewController, context: Context) {
    }
}
