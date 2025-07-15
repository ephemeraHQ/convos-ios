import SwiftUI

struct MessagesToolbarView: View {
    let conversationState: ConversationState
    let emptyConversationTitle: String

    init(conversationState: ConversationState,
         emptyConversationTitle: String = "New chat") {
        self.conversationState = conversationState
        self.emptyConversationTitle = emptyConversationTitle
    }

    @Environment(\.verticalSizeClass) private var verticalSizeClass: UserInterfaceSizeClass?

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
        HStack(spacing: DesignConstants.Spacing.step2x) {
            if let conversation = conversationState.conversation, !conversation.isDraft {
                ConversationAvatarView(conversation: conversation)
                    .padding(.vertical, avatarVerticalPadding)
            }

            VStack(alignment: .leading) {
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
        }
        .frame(height: barHeight)
    }

    enum Constant {
        static let regularHeight: CGFloat = 72.0
        static let compactHeight: CGFloat = 52.0
    }
}

#Preview {
    @Previewable @Environment(\.dismiss) var dismiss: DismissAction
    let conversationState = ConversationState(
        conversationRepository: MockConversationRepository()
    )

    MessagesToolbarView(
        conversationState: conversationState
    )
}
