import ConvosCore
import SwiftUI
import SwiftUIIntrospect

enum MessagesViewTopBarTrailingItem {
    case share, scan
}

struct MessagesView<BottomBarContent: View>: View {
    let conversation: Conversation
    @Binding var messages: [MessagesListItemType]
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
    let onboardingCoordinator: ConversationOnboardingCoordinator
    @FocusState.Binding var focusState: MessagesViewInputFocus?
    let focusCoordinator: FocusCoordinator
    let messagesTextFieldEnabled: Bool
    let onProfilePhotoTap: () -> Void
    let onSendMessage: () -> Void
    let onTapMessage: (AnyMessage) -> Void
    let onTapAvatar: (AnyMessage) -> Void
    let onDisplayNameEndedEditing: () -> Void
    let onProfileSettings: () -> Void
    let loadPreviousMessages: () -> Void
    @ViewBuilder let bottomBarContent: () -> BottomBarContent

    @State private var bottomBarHeight: CGFloat = 0.0
    var body: some View {
        Group {
            MessagesViewRepresentable(
                conversation: conversation,
                messages: messages,
                invite: invite,
                onTapMessage: onTapMessage,
                onTapAvatar: onTapAvatar,
                bottomBarHeight: bottomBarHeight
            )
            .ignoresSafeArea()
        }
//        MessagesListView(
//            conversation: conversation,
//            messages: $messages,
//            invite: invite,
//            focusCoordinator: focusCoordinator,
//            onTapMessage: onTapMessage,
//            onTapAvatar: onTapAvatar,
//            loadPrevious: loadPreviousMessages
//        )
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
                    focusCoordinator: focusCoordinator,
                    animateAvatarForQuickname: onboardingCoordinator.shouldAnimateAvatarForQuicknameSetup,
                    messagesTextFieldEnabled: messagesTextFieldEnabled,
                    onProfilePhotoTap: onProfilePhotoTap,
                    onSendMessage: onSendMessage,
                    onDisplayNameEndedEditing: onDisplayNameEndedEditing,
                    onProfileSettings: onProfileSettings
                )
            }
            .background(HeightReader())
            .onPreferenceChange(HeightPreferenceKey.self) { height in
                bottomBarHeight = height
            }
        }
        .introspect(.view, on: .iOS(.v26), customize: { view in
            view.keyboardLayoutGuide.keyboardDismissPadding = bottomBarHeight
        })
    }
}
