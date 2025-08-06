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
    let viewModelFocus: MessagesViewInputFocus?
    let onProfilePhotoTap: () -> Void
    let onSendMessage: () -> Void
    let onDisplayNameEndedEditing: () -> Void
    let onProfileSettings: () -> Void

    @State private var isExpanded: Bool = false
    @Namespace private var namespace: Namespace.ID

    var body: some View {
        GlassEffectContainer {
            ZStack {
                if !isExpanded {
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
                    .clipShape(.rect(cornerRadius: 26.0))
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 26.0))
                    .glassEffectID("input", in: namespace)
                    .glassEffectTransition(.matchedGeometry)
                }

                if isExpanded {
                    QuickEditView(
                        placeholderText: "\(emptyDisplayNamePlaceholder)...",
                        text: $displayName,
                        image: $profileImage,
                        focusState: $focusState,
                        focused: .displayName,
                        onSubmit: onDisplayNameEndedEditing,
                        onSettings: onProfileSettings
                    )
                    .frame(maxWidth: 320.0)
                    .padding(DesignConstants.Spacing.step6x)
                    .clipShape(.rect(cornerRadius: 40.0))
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 40.0))
                    .glassEffectID("profileEditor", in: namespace)
                    .glassEffectTransition(.matchedGeometry)
                }
            }
        }
        .padding(.horizontal, 10.0)
        .padding(.vertical, DesignConstants.Spacing.step2x)
        .onChange(of: viewModelFocus) { _, newValue in
            withAnimation(.bouncy(duration: 0.4, extraBounce: 0.01)) {
                isExpanded = newValue == .displayName ? true : false
            }
        }
    }
}
