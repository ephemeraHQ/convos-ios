import Observation
import SwiftUI

struct MessagesContainerView<Content: View>: UIViewControllerRepresentable {
    let conversationState: ConversationState
    let outgoingMessageWriter: any OutgoingMessageWriterProtocol
    let conversationConsentWriter: any ConversationConsentWriterProtocol
    let conversationLocalStateWriter: any ConversationLocalStateWriterProtocol
    @ViewBuilder let content: () -> Content

    @State private var text: String = ""
    @State private var sendButtonEnabled: Bool = false
    @State private var profile: Profile = .mock()
    @State private var profileName: String = ""
    @State private var showingProfileNameEditor: Bool = false

    @Environment(\.dismiss) private var dismiss: DismissAction

    func makeUIViewController(context: Context) -> MessagesContainerViewController {
        let viewController = MessagesContainerViewController(
            conversationState: conversationState,
            outgoingMessageWriter: outgoingMessageWriter,
            conversationConsentWriter: conversationConsentWriter,
            conversationLocalStateWriter: conversationLocalStateWriter,
            dismissAction: context.environment.dismiss,
            sendMessage: sendMessage,
            textDidChange: textDidChange(_:),
            textBinding: $text,
            sendButtonEnabled: $sendButtonEnabled,
            showingProfileNameEditor: $showingProfileNameEditor,
            profile: $profile,
            profileName: $profileName,
            joinConversation: joinConversation,
            deleteConversation: deleteConversation
        )
        viewController.messagesInputView.delegate = context.coordinator

        let hostingController = UIHostingController(
            rootView: content()
        )

        viewController.embedContentController(hostingController)
        return viewController
    }

    func updateUIViewController(_ uiViewController: MessagesContainerViewController, context: Context) {
        uiViewController.messagesInputView.sendButtonEnabled = sendButtonEnabled(for: conversationState.conversation)
        uiViewController.messagesInputView.text = text
    }

    // MARK: - Coordinator

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, MessagesInputViewDelegate {
        var containerView: MessagesContainerView

        init(_ containerView: MessagesContainerView) {
            self.containerView = containerView
        }

        @objc
        func messagesInputView(_ view: MessagesInputView, didChangeText text: String) {
            containerView.text = text
        }
    }

    // MARK: - Observations

    private func sendButtonEnabled(for conversation: Conversation?) -> Bool {
        let conversationHasMembers: Bool = !(conversation?.members.isEmpty ?? true)
        return conversationHasMembers && !text.isEmpty
    }

    // MARK: - Actions

    func sendMessage() {
        let messageText = text
        text = ""
        Task { [outgoingMessageWriter] in
            do {
                try await outgoingMessageWriter.send(text: messageText)
            } catch {
                Logger.error("Error sending message: \(error)")
            }
        }
    }

    func textDidChange(_ text: String) {
        let conversationHasMembers: Bool = !(conversationState.conversation?.members.isEmpty ?? true)
        sendButtonEnabled = conversationHasMembers && !text.isEmpty
    }

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
