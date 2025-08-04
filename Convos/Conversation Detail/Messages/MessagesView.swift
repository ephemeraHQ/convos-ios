import SwiftUI

struct MessagesView: View {
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
    var focusState: FocusState<MessagesViewInputFocus?>.Binding
    let onConversationInfoTap: () -> Void
    let onConversationNameEndedEditing: () -> Void
    let onConversationSettings: () -> Void
    let onProfilePhotoTap: () -> Void
    let onSendMessage: () -> Void
    let onDisplayNameEndedEditing: () -> Void
    let onProfileSettings: () -> Void
    let onScanInviteCode: () -> Void

    @State private var topBarHeight: CGFloat = 0.0
    @State private var bottomBarHeight: CGFloat = 0.0
    var body: some View {
        NavigationStack {
            ZStack {
                Group {
                    MessagesViewRepresentable(
                        conversationId: conversation.id,
                        messages: messages,
                        invite: invite,
                        topBarHeight: topBarHeight,
                        bottomBarHeight: bottomBarHeight
                    )
                    .ignoresSafeArea()
                }

                VStack {
                }
                .frame(maxHeight: .infinity)
                .safeAreaBar(edge: .top) {
                    MessagesTopBar(
                        conversation: conversation,
                        invite: invite,
                        untitledConversationPlaceholder: untitledConversationPlaceholder,
                        conversationNamePlaceholder: conversationNamePlaceholder,
                        conversationName: $conversationName,
                        conversationImage: $conversationImage,
                        focusState: focusState,
                        onConversationInfoTap: onConversationInfoTap,
                        onConversationNameEndedEditing: onConversationNameEndedEditing,
                        onConversationSettings: onConversationSettings,
                        onScanInviteCode: onScanInviteCode
                    )
                    .background(HeightReader())
                    .onPreferenceChange(HeightPreferenceKey.self) { height in
                        topBarHeight = height
                    }
                }
                .safeAreaBar(edge: .bottom) {
                    MessagesBottomBar(
                        profile: profile,
                        displayName: $displayName,
                        messageText: $messageText,
                        sendButtonEnabled: $sendButtonEnabled,
                        profileImage: $profileImage,
                        focusState: focusState,
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
    }
}
