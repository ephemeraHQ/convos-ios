import SwiftUI

enum MessagesViewInputFocus: Hashable {
    case message, displayName, conversationName
}

struct MessagesBottomBar: View {
    let profile: Profile
    @Binding var displayName: String
    let emptyDisplayNamePlaceholder: String = "Somebody"
    @Binding var messageText: String
    @Binding var sendButtonEnabled: Bool
    @Binding var profileImage: UIImage?
    @FocusState.Binding var focusState: MessagesViewInputFocus?
    let onProfilePhotoTap: () -> Void
    let onSendMessage: () -> Void
    let onDisplayNameEndedEditing: () -> Void
    let onProfileSettings: () -> Void

    @State private var progress: CGFloat = 0.0

    var body: some View {
        PrimarySecondaryContainerView(
            progress: progress,
            primaryProperties: .init(
                cornerRadius: 40.0,
                padding: DesignConstants.Spacing.stepX,
                fixedSizeHorizontal: false
            ),
            secondaryProperties: .init(
                cornerRadius: 40.0,
                padding: DesignConstants.Spacing.step6x,
                fixedSizeHorizontal: false
            )
        ) {
            MessagesInputView(
                profile: profile,
                profileImage: $profileImage,
                displayName: $displayName,
                emptyDisplayNamePlaceholder: emptyDisplayNamePlaceholder,
                messageText: $messageText,
                sendButtonEnabled: $sendButtonEnabled,
                focusState: $focusState,
                onProfilePhotoTap: onProfilePhotoTap,
                onSendMessage: onSendMessage
            )
        } secondaryContent: {
            QuickEditView(
                placeholderText: "\(emptyDisplayNamePlaceholder)...",
                text: $displayName,
                image: $profileImage,
                focusState: $focusState,
                focused: .displayName,
                onSubmit: onDisplayNameEndedEditing,
                onSettings: onProfileSettings
            )
        }
        .padding(.horizontal, 10.0)
        .padding(.vertical, DesignConstants.Spacing.step2x)
        .onChange(of: focusState) {
            Logger.info("Animating focus state change: \(focusState)")
            withAnimation(.bouncy(duration: 0.5, extraBounce: 0.2)) {
                progress = focusState == .displayName ? 1.0 : 0.0
            }
        }
    }
}
