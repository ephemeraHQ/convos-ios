import SwiftUI

struct SecurityLineView: View {
    enum Constant {
        static let regularHeight: CGFloat = 72.0
        static let compactHeight: CGFloat = 52.0
    }

    @Binding var path: [ConversationsRoute]
    private let conversationsState: ConversationsState
    private let deniedConversationsCount: ConversationsCountState
//    private let consentStateWriter: any ConversationConsentWriterProtocol
    let title: String = "Security line"
    let subtitle: String? = nil
    @Environment(\.verticalSizeClass) private var verticalSizeClass: UserInterfaceSizeClass?
    @Environment(\.dismiss) private var dismiss: DismissAction

    init(session: any SessionManagerProtocol, path: Binding<[ConversationsRoute]>) {
        conversationsState = .init(
            conversationsRepository: session.conversationsRepository(for: .securityLine)
        )
        deniedConversationsCount = .init(
            conversationsCountRepository: session.conversationsCountRepo(for: .denied)
        )
        _path = path
//        self.consentStateWriter = inboxesService.conversationConsentWriter()
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
                        NavigationLink(value: ConversationsRoute.conversation(conversation)) {
                            ConversationsListItem(conversation: conversation)
                        }
                    }
                }
            }
        }
        .navigationTitle("Security")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(id: "delete", placement: .topBarTrailing) {
                Button("Delete All", systemImage: "trash") {
//                    Task {
//                        do {
//                            try await consentStateWriter.deleteAll()
//                        } catch {
//                            Logger.error("Error deleting all conversations: \(error)")
//                        }
//                    }
                }
                .disabled(conversationsState.conversations.isEmpty)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !deniedConversationsCount.isEmpty {
                DeniedConversationsListItem(count: deniedConversationsCount.count)
            }
        }
    }
}

#Preview {
    @Previewable @State var path: [ConversationsRoute] = []
    let convos = ConvosClient.mock()

    NavigationStack {
        SecurityLineView(
            session: convos.session,
            path: $path
        )
    }
}
