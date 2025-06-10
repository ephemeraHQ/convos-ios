import SwiftUI

struct MessagesContainerView<Content: View>: View {
    let conversationState: ConversationState
    let outgoingMessageWriter: any OutgoingMessageWriterProtocol
    let conversationConsentWriter: any ConversationConsentWriterProtocol
    let conversationLocalStateWriter: any ConversationLocalStateWriterProtocol
    @ViewBuilder let content: (Binding<String>, Binding<Bool>) -> Content
    @State var text: String = ""
    @State var sendButtonEnabled: Bool = false

    @Environment(\.dismiss) var dismiss: DismissAction

    var showJoinConversation: Bool {
        guard let conversation = conversationState.conversation, !conversation.isDraft else {
            return false
        }

        switch conversation.consent {
        case .allowed:
            return false
        case .denied:
            return false
        case .unknown:
            return true
        }
    }

    var showInputBar: Bool {
        guard let conversation = conversationState.conversation else {
            return true // composer view
        }

        return conversation.consent != .denied
    }

    var body: some View {
        VStack(spacing: 0) {
            MessagesToolbarView(conversationState: conversationState)

            content($text, $sendButtonEnabled)
                .ignoresSafeArea(edges: .bottom)
        }
        .onChange(of: text) {
            updateSendButtonEnabled()
        }
        .onChange(of: conversationState.conversation) {
            updateSendButtonEnabled()
        }
        .onAppear {
            markConversationAsRead()
        }
        .onDisappear {
            markConversationAsRead()
        }
    }

    func updateSendButtonEnabled() {
        let conversationHasMembers: Bool = !(conversationState.conversation?.members.isEmpty ?? true)
        sendButtonEnabled = conversationHasMembers && !text.isEmpty
    }

    // MARK: - Actions

    func sendMessage() {
        let messageText = text
        text = ""
        Task {
            do {
                try await outgoingMessageWriter.send(text: messageText)
            } catch {
                Logger.error("Error sending message: \(error)")
            }
        }
    }

    func joinConversation() {
        guard let conversation = conversationState.conversation else { return }
        Task {
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
        Task {
            do {
                try await conversationConsentWriter.delete(conversation: conversation)
            } catch {
                Logger.error("Error deleting conversation: \(error)")
            }
        }
    }

    private func markConversationAsRead() {
        Task {
            do {
                try await conversationLocalStateWriter.setUnread(
                    false,
                    for: conversationState.conversationId
                )
            } catch {
                Logger.error("Failed marking conversation as read: \(error)")
            }
        }
    }
}

#Preview {
    let convos = ConvosClient.mock()
    let conversationId: String = "1"
    let conversationState = ConversationState(
        conversationRepository: convos.messaging.conversationRepository(
            for: conversationId
        )
    )
    NavigationStack {
        MessagesContainerView(
            conversationState: conversationState,
            outgoingMessageWriter: convos.messaging.messageWriter(for: conversationId),
            conversationConsentWriter: convos.messaging.conversationConsentWriter(),
            conversationLocalStateWriter: convos.messaging.conversationLocalStateWriter()
        ) { textBinding, sendButtonEnabled in
            MessagesView(
                messagesRepository: convos.messaging.messagesRepository(
                    for: conversationId
                ),
                textBinding: textBinding,
                sendButtonEnabled: sendButtonEnabled
            )
        }
    }
}
