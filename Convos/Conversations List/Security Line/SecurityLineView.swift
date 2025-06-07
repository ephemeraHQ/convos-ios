import SwiftUI

struct SecurityLineView: View {
    enum Constant {
        static let regularHeight: CGFloat = 72.0
        static let compactHeight: CGFloat = 52.0
    }

    @Binding var path: [ConversationsListView.Route]
    private let conversationsState: ConversationsState
    private let deniedConversationsCount: ConversationsCountState
    private let consentStateWriter: any ConversationConsentWriterProtocol
    let title: String = "Security line"
    let subtitle: String? = nil
    @Environment(\.verticalSizeClass) private var verticalSizeClass: UserInterfaceSizeClass?
    @Environment(\.dismiss) private var dismiss: DismissAction

    init(messagingService: any MessagingServiceProtocol, path: Binding<[ConversationsListView.Route]>) {
        conversationsState = .init(
            conversationsRepository: messagingService.conversationsRepository(for: .securityLine)
        )
        deniedConversationsCount = .init(
            conversationsCountRepository: messagingService.conversationsCountRepo(for: .denied)
        )
        _path = path
        self.consentStateWriter = messagingService.conversationConsentWriter()
    }

    var barHeight: CGFloat {
        verticalSizeClass == .compact ? Constant.compactHeight : Constant.regularHeight
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if conversationsState.conversations.isEmpty {
                    Spacer()
                    Text("All clear")
                        .font(.system(size: 16.0))
                        .foregroundStyle(.colorTextSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.vertical, DesignConstants.Spacing.step10x)
                    Spacer()
                } else {
                    ForEach(conversationsState.conversations) { conversation in
                        NavigationLink(value: ConversationsListView.Route.conversation(conversation)) {
                            ConversationsListItem(conversation: conversation)
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !deniedConversationsCount.isEmpty {
                DeniedConversationsListItem(count: deniedConversationsCount.count)
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
                    Task {
                        do {
                            try await consentStateWriter.deleteAll()
                        } catch {
                            Logger.error("Error deleting all conversations: \(error)")
                        }
                    }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 24.0))
                        .foregroundStyle(.colorTextPrimary)
                        .padding(.vertical, 10.0)
                        .padding(.horizontal, DesignConstants.Spacing.step2x)
                }
                .disabled(conversationsState.conversations.isEmpty)
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

    NavigationStack {
        SecurityLineView(
            messagingService: convos.messaging,
            path: $path
        )
        .toolbarVisibility(.hidden, for: .navigationBar)
    }
}
