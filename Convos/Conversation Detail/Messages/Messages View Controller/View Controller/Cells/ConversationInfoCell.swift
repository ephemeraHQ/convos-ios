import ConvosCore
import SwiftUI
import UIKit

class ConversationInfoCell: UICollectionViewCell {
    // MARK: - Initialization

    override init(frame: CGRect) {
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        self.contentConfiguration = nil
    }

    func setup(conversation: ConversationViewModel) {
        contentConfiguration = UIHostingConfiguration {
            VStack(alignment: .leading) {
                ConversationInfoPreview(conversation: conversation)
                    .frame(maxWidth: 320.0, alignment: .center)
                    .padding(.horizontal, DesignConstants.Spacing.step6x)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .margins(.vertical, 0.0)
    }

    override func preferredLayoutAttributesFitting(
        _ layoutAttributes: UICollectionViewLayoutAttributes
    ) -> UICollectionViewLayoutAttributes {
        layoutAttributesForHorizontalFittingRequired(layoutAttributes)
    }
}

struct ConversationInfoPreview: View {
    @Bindable var conversation: ConversationViewModel

    var body: some View {
        VStack {
            VStack(spacing: DesignConstants.Spacing.step2x) {
                ConversationAvatarView(
                    conversation: conversation.conversation,
                    conversationImage: conversation.conversationImage
                )
                .frame(width: 96.0, height: 96.0)

                VStack(spacing: DesignConstants.Spacing.stepHalf) {
                    Text(
                        conversation.conversationName.isEmpty ? conversation.conversation.displayName : conversation.conversationName
                    )
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.colorTextPrimary)
                    if !conversation.conversationDescription.isEmpty {
                        Text(conversation.conversationDescription)
                            .font(.subheadline.weight(.regular))
                            .foregroundStyle(.colorTextPrimary)
                    }
                }
                .padding(.horizontal, DesignConstants.Spacing.step2x)

                Text(conversation.conversation.membersCountString)
                    .font(.caption)
                    .foregroundStyle(.colorTextSecondary)
            }
            .multilineTextAlignment(.center)
            .padding(DesignConstants.Spacing.step6x)

//            if true {
//                Rectangle()
//                    .fill(.colorBorderSubtle)
//                    .frame(height: 1.0)
//                    .frame(maxWidth: .infinity)
//                VStack {
//
//                }
//                .padding(DesignConstants.Spacing.step6x)
//            }
        }
        .frame(maxWidth: .infinity)
        .background(.colorFillMinimal)
        .clipShape(RoundedRectangle(cornerRadius: DesignConstants.CornerRadius.mediumLarger))
    }
}

#Preview {
    ConversationInfoPreview(conversation: .mock)
}
