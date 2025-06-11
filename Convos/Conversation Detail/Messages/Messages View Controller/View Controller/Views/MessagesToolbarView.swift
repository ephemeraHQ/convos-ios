import SwiftUI

struct MessagesToolbarView: View {
    let conversationState: ConversationState
    let emptyConversationTitle: String
    let dismissAction: DismissAction

    init(conversationState: ConversationState,
         emptyConversationTitle: String = "New chat",
         dismissAction: DismissAction) {
        self.conversationState = conversationState
        self.emptyConversationTitle = emptyConversationTitle
        self.dismissAction = dismissAction
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

    var body: some View {
        HStack(spacing: 0.0) {
            Button {
                dismissAction()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 24.0))
                    .foregroundStyle(.colorTextPrimary)
                    .padding(.vertical, 10.0)
                    .padding(.horizontal, DesignConstants.Spacing.step2x)
            }
            .padding(.trailing, 2.0)

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
        .frame(height: barHeight)
        .padding(.leading, DesignConstants.Spacing.step2x)
        .padding(.trailing, DesignConstants.Spacing.step4x)
        .background(.colorBackgroundPrimary)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.colorBorderSubtle2)
                .frame(height: 1.0)
        }
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
    )
}
