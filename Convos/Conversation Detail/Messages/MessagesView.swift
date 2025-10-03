import ConvosCore
import SwiftUI

enum MessagesViewTopBarTrailingItem {
    case share, scan
}

struct MessagesView<BottomBarContent: View>: View {
    let conversation: Conversation
    let messages: [AnyMessage]
    let invite: Invite
    let profile: Profile
    let untitledConversationPlaceholder: String
    let conversationNamePlaceholder: String
    @Binding var conversationName: String
    @Binding var conversationImage: UIImage?
    @Binding var displayName: String
    @Binding var messageText: String
    @Binding var sendButtonEnabled: Bool
    @Binding var profileImage: UIImage?
    @FocusState.Binding var focusState: MessagesViewInputFocus?
    let messagesBottomBarEnabled: Bool
    let viewModelFocus: MessagesViewInputFocus?
    let onConversationInfoTap: () -> Void
    let onConversationNameEndedEditing: () -> Void
    let onConversationSettings: () -> Void
    let onProfilePhotoTap: () -> Void
    let onSendMessage: () -> Void
    let onTapMessage: (AnyMessage) -> Void
    let onDisplayNameEndedEditing: () -> Void
    let onProfileSettings: () -> Void
    @ViewBuilder let bottomBarContent: () -> BottomBarContent

    @State private var bottomBarHeight: CGFloat = 0.0
    var body: some View {
        Group {
            MessagesViewRepresentable(
                conversation: conversation,
                messages: messages,
                invite: invite,
                onTapMessage: onTapMessage,
                bottomBarHeight: bottomBarHeight
            )
            .ignoresSafeArea()
        }
        .safeAreaBar(edge: .bottom) {
            VStack(spacing: 0.0) {
                bottomBarContent()
                MessagesBottomBar(
                    profile: profile,
                    displayName: $displayName,
                    messageText: $messageText,
                    sendButtonEnabled: $sendButtonEnabled,
                    profileImage: $profileImage,
                    focusState: $focusState,
                    viewModelFocus: viewModelFocus,
                    onProfilePhotoTap: onProfilePhotoTap,
                    onSendMessage: onSendMessage,
                    onDisplayNameEndedEditing: onDisplayNameEndedEditing,
                    onProfileSettings: onProfileSettings
                )
                .disabled(!messagesBottomBarEnabled)
            }
            .background(HeightReader())
            .onPreferenceChange(HeightPreferenceKey.self) { height in
                bottomBarHeight = height
            }
        }
    }
}
