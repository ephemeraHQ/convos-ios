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
    @FocusState.Binding var focusState: MessagesViewInputFocus?
    let viewModelFocus: MessagesViewInputFocus?
    let onConversationInfoTap: () -> Void
    let onConversationNameEndedEditing: () -> Void
    let onConversationSettings: () -> Void
    let onProfilePhotoTap: () -> Void
    let onSendMessage: () -> Void
    let onDisplayNameEndedEditing: () -> Void
    let onProfileSettings: () -> Void
    let onScanInviteCode: () -> Void
    let onDeleteConversation: () -> Void
    let topBarLeadingItem: MessagesTopBar.LeadingItem
    let topBarTrailingItem: MessagesTopBar.TrailingItem
    let confirmDeletionBeforeDismissal: Bool

    @State private var topBarHeight: CGFloat = 0.0
    @State private var bottomBarHeight: CGFloat = 0.0
    var body: some View {
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
        .safeAreaBar(edge: .top) {
            MessagesTopBar(
                conversation: conversation,
                invite: invite,
                untitledConversationPlaceholder: untitledConversationPlaceholder,
                conversationNamePlaceholder: conversationNamePlaceholder,
                conversationName: $conversationName,
                conversationImage: $conversationImage,
                focusState: $focusState,
                viewModelFocus: viewModelFocus,
                onConversationInfoTap: onConversationInfoTap,
                onConversationNameEndedEditing: onConversationNameEndedEditing,
                onConversationSettings: onConversationSettings,
                onScanInviteCode: onScanInviteCode,
                onDeleteConversion: onDeleteConversation,
                leadingItem: topBarLeadingItem,
                trailingItem: topBarTrailingItem,
                confirmDeletionBeforeDismissal: confirmDeletionBeforeDismissal
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
