import SwiftUI

@Observable
class MessagesToolbarViewModel {
    var conversation: Conversation?
    var placeholderTitle: String = ""
    var subtitle: String?
    var onBack: (() -> Void)?
}

struct MessagesToolbarView: View {
    let viewModel: MessagesToolbarViewModel
    @Environment(\.verticalSizeClass) private var verticalSizeClass: UserInterfaceSizeClass?

    enum Constant {
        static let regularHeight: CGFloat = 72.0
        static let compactHeight: CGFloat = 52.0
    }

    var barHeight: CGFloat {
        verticalSizeClass == .compact ? Constant.compactHeight : Constant.regularHeight
    }

    var avatarVerticalPadding: CGFloat {
        DesignConstants.Spacing.step3x
    }

    var body: some View {
        HStack(spacing: 0.0) {
            Button {
                viewModel.onBack?()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 24.0))
                    .foregroundStyle(.colorTextPrimary)
                    .padding(.vertical, 10.0)
                    .padding(.horizontal, DesignConstants.Spacing.step2x)
            }
            .padding(.trailing, 2.0)

            if let conversation = viewModel.conversation {
                ConversationAvatarView(conversation: conversation)
                    .padding(.vertical, avatarVerticalPadding)
            }

            VStack(alignment: .leading, spacing: 2.0) {
                Text(viewModel.conversation?.title ?? viewModel.placeholderTitle)
                    .font(.system(size: 16.0))
                    .foregroundStyle(.colorTextPrimary)
                    .lineLimit(1)
                if let conversation = viewModel.conversation, conversation.kind == .group {
                    Text(conversation.membersCountString)
                        .font(.system(size: 12.0))
                        .foregroundStyle(.colorTextSecondary)
                        .lineLimit(1)
                }
            }
            .padding(.leading, DesignConstants.Spacing.step2x)

            Spacer()

            if let conversation = viewModel.conversation {
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
        .padding(.vertical, DesignConstants.Spacing.step4x)
        .padding(.leading, DesignConstants.Spacing.step2x)
        .padding(.trailing, DesignConstants.Spacing.step4x)
        .background(.clear)
    }
}

#Preview {
    let viewModel = MessagesToolbarViewModel()
    viewModel.conversation = .mock(
        kind: .group,
        members: [
            .mock(name: "John"),
            .mock(name: "Jane"),
            .mock(name: "Tom")
        ]
    )
    return MessagesToolbarView(viewModel: viewModel)
}
