import ConvosCore
import SwiftUI

struct MessagesView: View {
    enum TopBarTrailingItem {
        case share, scan
    }

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
    let viewModelFocus: MessagesViewInputFocus?
    let onConversationInfoTap: () -> Void
    let onConversationNameEndedEditing: () -> Void
    let onConversationSettings: () -> Void
    let onProfilePhotoTap: () -> Void
    let onSendMessage: () -> Void
    let onTapMessage: (AnyMessage) -> Void
    let onDisplayNameEndedEditing: () -> Void
    let onProfileSettings: () -> Void
    let onScanInviteCode: () -> Void
    let onDeleteConversation: () -> Void
    let confirmDeletionBeforeDismissal: Bool

    @State private var topBarHeight: CGFloat = 0.0
    @State private var bottomBarHeight: CGFloat = 0.0
    var body: some View {
        Group {
            MessagesViewRepresentable(
                conversation: conversation,
                messages: messages,
                invite: invite,
                onTapMessage: onTapMessage,
                topBarHeight: topBarHeight,
                bottomBarHeight: bottomBarHeight
            )
            .ignoresSafeArea()
        }
        .safeAreaBar(edge: .bottom) {
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
            .background(HeightReader())
            .onPreferenceChange(HeightPreferenceKey.self) { height in
                bottomBarHeight = height
            }
        }
    }
}
