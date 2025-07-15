import SwiftUI

struct SecurityLineView: View {
    enum Constant {
        static let regularHeight: CGFloat = 72.0
        static let compactHeight: CGFloat = 52.0
    }

    @Binding var path: [ConversationsRoute]
    private let session: any SessionManagerProtocol
    private let conversationsState: ConversationsState
    private let deniedConversationsCount: ConversationsCountState
    let title: String = "Security line"
    let subtitle: String? = nil
    @Environment(\.verticalSizeClass) private var verticalSizeClass: UserInterfaceSizeClass?
    @Environment(\.dismiss) private var dismiss: DismissAction

    init(session: any SessionManagerProtocol, path: Binding<[ConversationsRoute]>) {
        self.session = session
        conversationsState = .init(
            conversationsRepository: session.conversationsRepository(for: .securityLine)
        )
        deniedConversationsCount = .init(
            conversationsCountRepository: session.conversationsCountRepo(for: .denied)
        )
        _path = path
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
                    deleteAll()
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

    private func deleteAll() {
        let inboxIds = Set<String>(conversationsState.conversations.map { $0.inboxId })
        let messagingServices = inboxIds.map { session.messagingService(for: $0) }
        let consentStateWriters = messagingServices.map { $0.conversationConsentWriter() }
        Task {
            await withTaskGroup(of: Void.self) { group in
                for writer in consentStateWriters {
                    group.addTask {
                        do {
                            try await writer.deleteAll()
                        } catch {
                            Logger.error("Error deleting all conversations: \(error)")
                        }
                    }
                }
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
