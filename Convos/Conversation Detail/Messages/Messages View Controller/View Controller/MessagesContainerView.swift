import Observation
import SwiftUI

struct MessagesContainerView<Content: View>: UIViewControllerRepresentable {
    let conversationState: ConversationState
    let outgoingMessageWriter: any OutgoingMessageWriterProtocol
    let conversationConsentWriter: any ConversationConsentWriterProtocol
    let conversationLocalStateWriter: any ConversationLocalStateWriterProtocol
    @ViewBuilder let content: () -> Content

    @State private var inputViewModel: MessagesInputViewModel

    @Environment(\.dismiss) private var dismiss: DismissAction

    init(
        conversationState: ConversationState,
        outgoingMessageWriter: any OutgoingMessageWriterProtocol,
        conversationConsentWriter: any ConversationConsentWriterProtocol,
        conversationLocalStateWriter: any ConversationLocalStateWriterProtocol,
        content: @escaping () -> Content,
    ) {
        self.conversationState = conversationState
        self.outgoingMessageWriter = outgoingMessageWriter
        self.conversationConsentWriter = conversationConsentWriter
        self.conversationLocalStateWriter = conversationLocalStateWriter
        self.content = content
        _inputViewModel = State(initialValue: .init(
            conversationState: conversationState,
            outgoingMessageWriter: outgoingMessageWriter,
            profile: .mock(name: "")
        ))
    }

    func makeUIViewController(context: Context) -> MessagesContainerViewController {
        let viewController = MessagesContainerViewController(
            conversationState: conversationState,
            messagesInputViewModel: inputViewModel,
            outgoingMessageWriter: outgoingMessageWriter,
            conversationConsentWriter: conversationConsentWriter,
            conversationLocalStateWriter: conversationLocalStateWriter,
            dismissAction: context.environment.dismiss,
            joinConversation: joinConversation,
            deleteConversation: deleteConversation
        )

        let hostingController = UIHostingController(
            rootView: content()
        )

        viewController.embedContentController(hostingController)
        return viewController
    }

    func updateUIViewController(_ uiViewController: MessagesContainerViewController, context: Context) {
    }

    // MARK: - Actions

    func joinConversation() {
        guard let conversation = conversationState.conversation else { return }
        Task { [conversationConsentWriter] in
            do {
                try await conversationConsentWriter.join(conversation: conversation)
            } catch {
                Logger.error("Error joining conversation: \(error)")
            }
        }
    }

    func deleteConversation() {
        guard let conversation = conversationState.conversation else { return }
        dismiss()
        Task { [conversationConsentWriter] in
            do {
                try await conversationConsentWriter.delete(conversation: conversation)
            } catch {
                Logger.error("Error deleting conversation: \(error)")
            }
        }
    }
}
