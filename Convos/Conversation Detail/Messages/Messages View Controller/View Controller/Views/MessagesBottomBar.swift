import ConvosCore
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
    let animateAvatarForQuickname: Bool
    let messagesTextFieldEnabled: Bool
    let onProfilePhotoTap: () -> Void
    let onSendMessage: () -> Void
    let onDisplayNameEndedEditing: () -> Void
    let onProfileSettings: () -> Void

    @State private var progress: CGFloat = 0.0
    //    @State private var isExpanded: Bool = false
    @Namespace private var namespace: Namespace.ID

    var body: some View {
        PrimarySecondaryContainerView(
            progress: progress,
            primaryProperties: .init(
                cornerRadius: (MessagesInputView.defaultHeight + (DesignConstants.Spacing.step4x)) / 2.0,
                padding: DesignConstants.Spacing.step2x,
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
                animateAvatarForQuickname: animateAvatarForQuickname,
                messagesTextFieldEnabled: messagesTextFieldEnabled,
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
//        GlassEffectContainer {
//            ZStack {
//                if !isExpanded {
//                    MessagesInputView(
//                        profile: profile,
//                        profileImage: $profileImage,
//                        displayName: $displayName,
//                        emptyDisplayNamePlaceholder: emptyDisplayNamePlaceholder,
//                        messageText: $messageText,
//                        sendButtonEnabled: $sendButtonEnabled,
//                        focusState: $focusState,
//                        onProfilePhotoTap: onProfilePhotoTap,
//                        onSendMessage: onSendMessage
//                    )
//                    .clipShape(.rect(cornerRadius: 26.0))
//                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 26.0))
//                    .glassEffectID("input", in: namespace)
//                    .glassEffectTransition(.matchedGeometry)
//                }
//
//                if isExpanded {
//                    QuickEditView(
//                        placeholderText: "\(emptyDisplayNamePlaceholder)...",
//                        text: $displayName,
//                        image: $profileImage,
//                        focusState: $focusState,
//                        focused: .displayName,
//                        onSubmit: onDisplayNameEndedEditing,
//                        onSettings: onProfileSettings
//                    )
//                    .frame(maxWidth: 320.0)
//                    .padding(DesignConstants.Spacing.step6x)
//                    .clipShape(.rect(cornerRadius: 40.0))
//                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 40.0))
//                    .glassEffectID("profileEditor", in: namespace)
//                    .glassEffectTransition(.matchedGeometry)
//                }
//            }
//        }
        .padding(.horizontal, 10.0)
        .padding(.vertical, DesignConstants.Spacing.step2x)
        .onChange(of: viewModelFocus) { _, newValue in
            withAnimation(.bouncy(duration: 0.5, extraBounce: 0.2)) {
                progress = newValue == .displayName ? 1.0 : 0.0
            }
//            withAnimation(.bouncy(duration: 0.4, extraBounce: 0.01)) {
//                isExpanded = newValue == .displayName ? true : false
//            }
        }
    }
}

#Preview {
    @Previewable @State var profile: Profile = .mock()
    @Previewable @State var profileName: String = ""
    @Previewable @State var messageText: String = ""
    @Previewable @State var sendButtonEnabled: Bool = false
    @Previewable @State var profileImage: UIImage?
    @Previewable var animateAvatarForQuickname: Bool = false
    @Previewable @FocusState var focusState: MessagesViewInputFocus?
    @Previewable @State var viewModelFocus: MessagesViewInputFocus?
    MessagesBottomBar(
        profile: profile,
        displayName: $profileName,
        messageText: $messageText,
        sendButtonEnabled: $sendButtonEnabled,
        profileImage: $profileImage,
        focusState: $focusState,
        viewModelFocus: viewModelFocus,
        animateAvatarForQuickname: animateAvatarForQuickname,
        messagesTextFieldEnabled: true,
        onProfilePhotoTap: {
            viewModelFocus = .displayName
        },
        onSendMessage: {},
        onDisplayNameEndedEditing: {
            viewModelFocus = .message
        },
        onProfileSettings: {}
    )
}
