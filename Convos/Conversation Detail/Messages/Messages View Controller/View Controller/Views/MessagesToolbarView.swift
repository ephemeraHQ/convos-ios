import SwiftUI

struct MessagesToolbarView: View {
    let conversationState: ConversationState
    let emptyConversationTitle: String
    let dismissAction: DismissAction
    let onInfoTap: () -> Void

    init(conversationState: ConversationState,
         emptyConversationTitle: String = "New chat",
         dismissAction: DismissAction,
         onInfoTap: @escaping () -> Void) {
        self.conversationState = conversationState
        self.emptyConversationTitle = emptyConversationTitle
        self.dismissAction = dismissAction
        self.onInfoTap = onInfoTap
    }

    @Environment(\.verticalSizeClass) private var verticalSizeClass: UserInterfaceSizeClass?

    enum Constant {
        static let regularHeight: CGFloat = 72.0
        static let compactHeight: CGFloat = 52.0
    }

    var barHeight: CGFloat {
        verticalSizeClass == .compact ? Constant.compactHeight : Constant.regularHeight
    }

    var avatarVerticalPadding: CGFloat {
        verticalSizeClass == .compact ?
        DesignConstants.Spacing.step2x :
        DesignConstants.Spacing.step4x
    }

    var title: String {
        if let conversation = conversationState.conversation,
           !conversation.isDraft {
            conversation.title
        } else {
            emptyConversationTitle
        }
    }

    var needsAvatarSpacing: Bool {
        // Only add spacing when we have a real conversation with an avatar
        conversationState.conversation?.isDraft == false
    }

    var body: some View {
        CustomToolbarView(
            onBack: { dismissAction() },
            showBackText: false,
            showBottomBorder: conversationState.conversation?.isDraft ?? true,
            rightContent: {
                HStack(spacing: 0) {
                    // Middle content (avatar and title)
                    Button(action: onInfoTap) {
                        HStack(spacing: 0) {
                            if let conversation = conversationState.conversation, !conversation.isDraft {
                                ConversationAvatarView(conversation: conversation)
                                    .padding(.vertical, avatarVerticalPadding)
                            }
                            VStack(alignment: .leading, spacing: 2.0) {
                                Text(title)
                                    .font(.system(size: 16.0))
                                    .foregroundStyle(.colorTextPrimary)
                                    .lineLimit(1)
                                if let conversation = conversationState.conversation, conversation.kind == .group {
                                    Text(conversation.membersCountString)
                                        .font(.system(size: 12.0))
                                        .foregroundStyle(.colorTextSecondary)
                                        .lineLimit(1)
                                }
                            }
                            .padding(.leading, needsAvatarSpacing ? DesignConstants.Spacing.step2x : 0)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(conversationState.conversation?.isDraft ?? true)

                    Spacer()

                    // Right side buttons
                    if let conversation = conversationState.conversation {
                        switch conversation.kind {
                        case .group:
                            Button {
                            } label: {
                                Image(systemName: "qrcode")
                                    .font(.system(size: 24.0))
                                    .foregroundStyle(.colorTextPrimary)
                                    .padding(.vertical, 10.0)
                                    .padding(.horizontal, DesignConstants.Spacing.step2x)
                            }
                        case .dm:
                            Button {
                            } label: {
                                Image(systemName: "timer")
                                    .font(.system(size: 24.0))
                                    .foregroundStyle(.colorTextPrimary)
                                    .padding(.vertical, 10.0)
                                    .padding(.horizontal, DesignConstants.Spacing.step2x)
                            }
                        }
                    }
                }
            }
        )
        .frame(height: barHeight)
    }
}

#Preview {
    @Previewable @Environment(\.dismiss) var dismiss: DismissAction
    let convos = ConvosClient.mock()
    let conversationId: String = "1"
    let conversationState = ConversationState(
        conversationRepository: convos.messaging.conversationRepository(
            for: conversationId
        )
    )
    MessagesToolbarView(
        conversationState: conversationState, dismissAction: dismiss
    ) {
        // Placeholder for onInfoTap
    }
}
