import SwiftUI

enum ConversationsRoute: Hashable {
    case conversation(ConversationViewDependencies)
}

struct ConversationDetail {
    let conversation: Conversation
    let messagingService: AnyMessagingService
}

struct ConversationsView: View {
    let session: any SessionManagerProtocol
    @Namespace var namespace: Namespace.ID
    @State var isPresentingComposer: Bool = false
    @State var isPresentingJoinConversation: Bool = false
    @State var presentingExplodeConfirmation: Bool = false
    @State var path: [ConversationsRoute] = []
    @Environment(\.dismiss) var dismiss: DismissAction

    var body: some View {
        NavigationStack(path: $path) {
            ConversationsListView(
                session: session,
                isPresentingComposer: $isPresentingComposer,
                isPresentingJoinConversation: $isPresentingJoinConversation,
                path: $path
            )
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        presentingExplodeConfirmation = true
                    } label: {
                        HStack(spacing: DesignConstants.Spacing.step2x) {
                            Circle()
                                .fill(.colorOrange)
                                .frame(width: 24.0, height: 24.0)

                            Text("Convos")
                                .font(.system(size: 16.0, weight: .medium))
                                .foregroundStyle(.colorTextPrimary)
                        }
                        .padding(10)
                    }
                    .glassEffect(.clear.tint(.white))
                    .confirmationDialog("", isPresented: $presentingExplodeConfirmation) {
                        Button("Explode", role: .destructive) {
                            do {
                                try session.deleteAllAccounts()
                            } catch {
                                Logger.error("Error deleting all accounts: \(error)")
                            }
                        }

                        Button("Wipe all local data", role: .destructive) {
                            wipeAllAppData()
                        }

                        Button("Cancel") {
                            presentingExplodeConfirmation = false
                        }
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Filter", systemImage: "line.3.horizontal.decrease") {
                        //
                    }
                    .disabled(true)
                }

                ToolbarItem(placement: .bottomBar) {
                    Spacer()
                }

                ToolbarItem(placement: .bottomBar) {
                    Button("Compose", systemImage: "plus") {
                        isPresentingComposer = true
                    }
                }
                .matchedTransitionSource(
                    id: "composer-transition-source",
                    in: namespace
                )
            }
            .fullScreenCover(isPresented: $isPresentingJoinConversation) {
                NewConversationView(session: session, presentingJoinConversation: true)
                    .ignoresSafeArea()
                    .background(.white)
                    .interactiveDismissDisabled()
            }
            .fullScreenCover(isPresented: $isPresentingComposer) {
                NewConversationView(session: session, presentingJoinConversation: false)
                    .ignoresSafeArea()
                    .background(.white)
                    .interactiveDismissDisabled()
                    .navigationTransition(
                        .zoom(
                            sourceID: "composer-transition-source",
                            in: namespace
                        )
                    )
            }
        }
        .background(.colorBackgroundPrimary)
    }

    private func wipeAllAppData() {
        do {
            // Delete all accounts and database content
            try session.deleteAllAccounts()

            // Get the app group container URL
            let environment = ConfigManager.shared.currentEnvironment
            let appGroupId = environment.appGroupIdentifier
            guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) else {
                Logger.error("Failed to get container URL for app group: \(appGroupId)")
                return
            }

            // List all files and directories in the app group container
            let fileManager = FileManager.default
            let contents = try fileManager.contentsOfDirectory(at: containerURL, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey])

            Logger.info("📁 App Group Container Contents (\(contents.count) items):")
            Logger.info("📍 Path: \(containerURL.path)")

            for url in contents {
                let resourceValues = try url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
                let isDirectory = resourceValues.isDirectory ?? false
                let fileSize = resourceValues.fileSize ?? 0
                let fileName = url.lastPathComponent

                if isDirectory {
                    Logger.info("📂 \(fileName)/")
                } else {
                    let sizeString = ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
                    Logger.info("📄 \(fileName) (\(sizeString))")
                }
            }

            // Delete specific XMTP files and salt files
            var deletedCount = 0

            for url in contents {
                let fileName = url.lastPathComponent

                // Delete XMTP database files and salt files
                if fileName.hasPrefix("xmtp-localhost-") || fileName.hasSuffix(".sqlcipher_salt") {
                    do {
                        try fileManager.removeItem(at: url)
                        Logger.info("✅ Deleted: \(fileName)")
                        deletedCount += 1
                    } catch {
                        Logger.error("❌ Failed to delete \(fileName): \(error)")
                    }
                }
            }

            Logger.info("🧹 Deleted \(deletedCount) XMTP files")
        } catch {
            Logger.error("Error listing app data: \(error)")
        }
    }
}

#Preview {
    @Previewable @State var path: [ConversationsRoute] = []
    let convos = ConvosClient.mock()
    ConversationsView(
        session: convos.session
    )
}
