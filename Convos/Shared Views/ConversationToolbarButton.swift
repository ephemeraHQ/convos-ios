import SwiftUI

struct ConversationToolbarButton: View {
    let conversation: Conversation
    let draftTitle: String
    let subtitle: String
    let action: () -> Void

    init(
        conversation: Conversation,
        draftTitle: String = "New convo",
        subtitle: String = "Customize",
        action: @escaping () -> Void = {}
    ) {
        self.conversation = conversation
        self.draftTitle = draftTitle
        self.subtitle = subtitle
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0.0) {
                ConversationAvatarView(conversation: conversation)
                    .frame(width: 36.0, height: 36.0)

                VStack(alignment: .leading, spacing: 0.0) {
                    if !conversation.isDraft, let name = conversation.name, !name.isEmpty {
                        Text(name)
                            .font(.system(size: 16.0, weight: .medium))
                            .foregroundStyle(.colorTextPrimary)
                    } else {
                        Text(draftTitle)
                            .font(.system(size: 16.0, weight: .medium))
                    }
                    Text(subtitle)
                        .font(.system(size: 12.0, weight: .regular))
                        .foregroundStyle(.colorTextSecondary)
                }
                .padding(.horizontal, DesignConstants.Spacing.step2x)
            }
        }
        .padding(DesignConstants.Spacing.step2x)
        .glassEffect()
        .padding(.top, DesignConstants.Spacing.stepX) // @jarodl avoids dynamic island
    }
}

#Preview {
    @Previewable @State var conversation: Conversation = .mock()

    VStack {
        ConversationToolbarButton(conversation: conversation) {
            print("Button tapped")
        }
    }
}
