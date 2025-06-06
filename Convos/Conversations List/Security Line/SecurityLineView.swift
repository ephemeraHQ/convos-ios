import SwiftUI

struct SecurityLineView: View {
    enum Constant {
        static let regularHeight: CGFloat = 72.0
        static let compactHeight: CGFloat = 52.0
    }

    @Binding var path: [ConversationsListView.Route]
    var conversationsState: ConversationsState
    let title: String = "Security line"
    let subtitle: String? = nil
    @Environment(\.verticalSizeClass) private var verticalSizeClass: UserInterfaceSizeClass?
    @Environment(\.dismiss) private var dismiss: DismissAction

    var barHeight: CGFloat {
        verticalSizeClass == .compact ? Constant.compactHeight : Constant.regularHeight
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(conversationsState.securityLineConversations) { conversation in
                    NavigationLink(value: ConversationsListView.Route.conversation(conversation)) {
                        ConversationsListItem(conversation: conversation)
                    }
                }
            }
        }
        .safeAreaInset(edge: .top) {
            HStack(spacing: 0.0) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 24.0))
                        .foregroundStyle(.colorTextPrimary)
                        .padding(.vertical, 10.0)
                        .padding(.horizontal, DesignConstants.Spacing.step2x)
                }
                .padding(.trailing, 2.0)

                VStack(alignment: .leading, spacing: 2.0) {
                    Text(title)
                        .font(.system(size: 16.0))
                        .foregroundStyle(.colorTextPrimary)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 12.0))
                            .foregroundStyle(.colorTextSecondary)
                            .lineLimit(1)
                    }
                }
                .padding(.leading, DesignConstants.Spacing.step2x)

                Spacer()

                Button {
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 24.0))
                        .foregroundStyle(.colorTextPrimary)
                        .padding(.vertical, 10.0)
                        .padding(.horizontal, DesignConstants.Spacing.step2x)
                }
            }
            .padding(.leading, DesignConstants.Spacing.step2x)
            .padding(.trailing, DesignConstants.Spacing.step4x)
            .padding(.vertical, DesignConstants.Spacing.step4x)
            .frame(height: barHeight)
            .background(.colorBackgroundPrimary)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(.colorBorderSubtle2)
                    .frame(height: 1.0)
            }
        }
    }
}

#Preview {
    @Previewable @State var path: [ConversationsListView.Route] = []
    let convos = ConvosClient.mock()
    let conversationsRepository = convos.messaging.conversationsRepository()

    NavigationStack {
        SecurityLineView(
            path: $path,
            conversationsState: .init(
                conversationsRepository: conversationsRepository
            )
        )
        .toolbarVisibility(.hidden, for: .navigationBar)
    }
}
