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
        verticalSizeClass == .compact ? CustomToolbarConstants.compactHeight : CustomToolbarConstants.regularHeight
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
        HStack(spacing: 0.0) {
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
            .padding(.leading, DesignConstants.Spacing.step2x)

            Spacer()

//            if let conversation = conversationState.conversation {
//                switch conversation.kind {
//                case .group:
//                    Button {
//                    } label: {
//                        Image(systemName: "qrcode")
//                            .font(.system(size: 24.0))
//                            .foregroundStyle(.colorTextPrimary)
//                            .padding(.vertical, 10.0)
//                            .padding(.horizontal, DesignConstants.Spacing.step2x)
//                    }
//                case .dm:
//                    Button {
//                    } label: {
//                        Image(systemName: "timer")
//                            .font(.system(size: 24.0))
//                            .foregroundStyle(.colorTextPrimary)
//                            .padding(.vertical, 10.0)
//                            .padding(.horizontal, DesignConstants.Spacing.step2x)
//                    }
//                }
//            }
        }
        .frame(height: barHeight)
        .padding(.leading, DesignConstants.Spacing.step2x)
        .padding(.trailing, DesignConstants.Spacing.step4x)
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
