import SwiftUI

struct ConversationInfoButton: View {
    let conversation: Conversation
    let placeholderName: String
    @Binding var conversationName: String
    @Binding var conversationImage: UIImage?
    var focusState: FocusState<MessagesViewInputFocus?>.Binding
    let onConversationInfoTapped: () -> Void
    let onConversationNameEndedEditing: () -> Void
    let onConversationSettings: () -> Void

    @State private var progress: CGFloat = 0.0

    var body: some View {
        PrimarySecondaryContainerView(
            progress: progress,
            primaryProperties: .init(
                cornerRadius: nil,
                padding: DesignConstants.Spacing.step2x,
                fixedSizeHorizontal: false
            ),
            secondaryProperties: .init(
                cornerRadius: 40.0,
                padding: DesignConstants.Spacing.step6x,
                fixedSizeHorizontal: true
            )
        ) {
            ConversationToolbarButton(
                conversation: conversation,
                action: onConversationInfoTapped
            )
        } secondaryContent: {
            QuickEditView(
                placeholderText: conversationName.isEmpty ? placeholderName : conversationName,
                text: $conversationName,
                image: $conversationImage,
                focusState: focusState,
                focused: .conversationName,
                onSubmit: onConversationNameEndedEditing,
                onSettings: onConversationSettings)
        }
        .onChange(of: focusState.wrappedValue) { _, newValue in
            withAnimation(.bouncy(duration: 0.5, extraBounce: 0.2)) {
                progress = newValue == .conversationName ? 1.0 : 0.0
            }
        }
    }
}

#Preview {
    @Previewable @State var conversationName: String = ""
    @Previewable @State var conversationImage: UIImage?
    @Previewable @FocusState var focusState: MessagesViewInputFocus?

    let conversation: Conversation = .mock()
    let placeholderName: String = conversation.name ?? "Name"

    ConversationInfoButton(
        conversation: conversation,
        placeholderName: placeholderName,
        conversationName: $conversationName,
        conversationImage: $conversationImage,
        focusState: $focusState,
        onConversationInfoTapped: {
            focusState = .conversationName
        },
        onConversationNameEndedEditing: {
            focusState = nil
        },
        onConversationSettings: {}
    )
}
