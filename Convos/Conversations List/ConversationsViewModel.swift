import Combine
import ConvosCore
import Foundation
import Observation

@Observable
final class ConversationsViewModel {
    // MARK: - Public

    var selectedConversation: Conversation? {
        get {
            selectedConversationViewModel?.conversation
        }
        set {
            if let selectedConversation = newValue {
                selectedConversationViewModel = ConversationViewModel(
                    conversation: selectedConversation,
                    session: session
                )
                markConversationAsRead(selectedConversation)
            } else {
                selectedConversationViewModel = nil
            }

            // Notify that active conversation has changed
            NotificationCenter.default.post(
                name: .activeConversationChanged,
                object: nil,
                userInfo: ["conversationId": newValue?.id as Any]
            )
        }
    }
    private(set) var selectedConversationViewModel: ConversationViewModel?
    var newConversationViewModel: NewConversationViewModel? {
        didSet {
            if newConversationViewModel == nil {
                NotificationCenter.default.post(
                    name: .activeConversationChanged,
                    object: nil,
                    userInfo: ["conversationId": nil]
                )
            }
        }
    }
    var presentingExplodeInfo: Bool = false
    let maxNumberOfConvos: Int = 20
    var presentingMaxNumberOfConvosReachedInfo: Bool = false
    private var maxNumberOfConvosReached: Bool {
        conversationsCount >= maxNumberOfConvos
    }
    private(set) var conversations: [Conversation] = []
    private var conversationsCount: Int = 0

    var pinnedConversations: [Conversation] {
        conversations.filter { $0.isPinned }.filter { $0.kind == .group } // @jarodl temporarily filtering out dms
    }
    var unpinnedConversations: [Conversation] {
        conversations.filter { !$0.isPinned }.filter { $0.kind == .group } // @jarodl temporarily filtering out dms
    }

    // MARK: - Private

    private let session: any SessionManagerProtocol
    private let conversationsRepository: any ConversationsRepositoryProtocol
    private let conversationsCountRepository: any ConversationsCountRepositoryProtocol
    private var localStateWriters: [String: any ConversationLocalStateWriterProtocol] = [:]
    private var cancellables: Set<AnyCancellable> = .init()
    private var leftConversationObserver: Any?

    init(
        session: any SessionManagerProtocol,
        conversationsRepository: any ConversationsRepositoryProtocol,
        conversationsCountRepository: any ConversationsCountRepositoryProtocol
    ) {
        self.session = session
        self.conversationsRepository = conversationsRepository
        self.conversationsCountRepository = conversationsCountRepository
        do {
            self.conversations = try conversationsRepository.fetchAll()
            self.conversationsCount = try conversationsCountRepository.fetchCount()
        } catch {
            Logger.error("Error fetching conversations: \(error)")
            self.conversations = []
        }
        observe()
    }

    deinit {
        if let leftConversationObserver {
            NotificationCenter.default.removeObserver(leftConversationObserver)
        }
        cancellables.removeAll()
    }

    func handleURL(_ url: URL) {
        guard let destination = DeepLinkHandler.destination(for: url) else {
            return
        }

        switch destination {
        case .requestToJoin(inviteCode: let inviteCode):
            join(from: inviteCode)
        }
    }

    func onStartConvo() {
        guard !maxNumberOfConvosReached else {
            presentingMaxNumberOfConvosReachedInfo = true
            return
        }
        newConversationViewModel = .init(
            session: session,
            autoCreateConversation: true,
            delegate: self
        )
    }

    func onJoinConvo() {
        guard !maxNumberOfConvosReached else {
            presentingMaxNumberOfConvosReachedInfo = true
            return
        }
        newConversationViewModel = .init(
            session: session,
            showingFullScreenScanner: true,
            delegate: self
        )
    }

    private func join(from inviteCode: String) {
        guard !maxNumberOfConvosReached else {
            presentingMaxNumberOfConvosReachedInfo = true
            return
        }
        // This creates a request to join via invite code
        // For deep links, we want to directly join without showing the scanner
        // All validation (already joined, invalid codes, etc.) is handled by ConversationStateMachine
        newConversationViewModel = .init(
            session: session,
            delegate: self,
        )
        _ = newConversationViewModel?.join(inviteUrlString: inviteCode)
    }

    func deleteAllInboxes() {
        selectedConversation = nil
        Task { [weak self] in
            guard let self else { return }
            do {
                try await session.deleteAllInboxes()
                await MainActor.run { self.localStateWriters.removeAll() }
            } catch {
                Logger.error("Error deleting all accounts: \(error)")
            }
        }
    }

    func leave(conversation: Conversation) {
        if selectedConversation == conversation {
            selectedConversation = nil
        }

        Task { [weak self] in
            guard let self else { return }
            do {
                try await session.deleteInbox(inboxId: conversation.inboxId)
                _ = await MainActor.run { self.localStateWriters.removeValue(forKey: conversation.inboxId) }
            } catch {
                Logger.error("Error leaving convo: \(error.localizedDescription)")
            }
        }
    }

    private func observe() {
        leftConversationObserver = NotificationCenter.default
            .addObserver(forName: .leftConversationNotification, object: nil, queue: .main) { [weak self] notification in
                guard let self else { return }
                guard let conversationId: String = notification.userInfo?["conversationId"] as? String else {
                    return
                }
                Logger.info("Left conversation notification received for conversation: \(conversationId)")
                if selectedConversation?.id == conversationId {
                    selectedConversation = nil
                }
                if newConversationViewModel?.conversationViewModel?.conversation.id == conversationId {
                    newConversationViewModel = nil
                }
            }

        // Observe explosion notification taps
        NotificationCenter.default
            .publisher(for: .explosionNotificationTapped)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.presentingExplodeInfo = true
            }
            .store(in: &cancellables)

        // Observe conversation notification taps
        NotificationCenter.default
            .publisher(for: .conversationNotificationTapped)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleConversationNotificationTap(notification)
            }
            .store(in: &cancellables)

        conversationsCountRepository.conversationsCount
            .receive(on: DispatchQueue.main)
            .sink { [weak self] conversationsCount in
                self?.conversationsCount = conversationsCount
            }
            .store(in: &cancellables)
        conversationsRepository.conversationsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] conversations in
                self?.conversations = conversations
            }
            .store(in: &cancellables)
    }

    private func handleConversationNotificationTap(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let inboxId = userInfo["inboxId"] as? String,
              let conversationId = userInfo["conversationId"] as? String else {
            Logger.warning("Conversation notification tapped but missing required userInfo")
            return
        }

        Logger.info("Handling conversation notification tap for inboxId: \(inboxId), conversationId: \(conversationId)")

        if let conversation = conversations.first(where: { $0.id == conversationId }) {
            Logger.info("Found conversation, selecting it")
            selectedConversation = conversation
        } else {
            Logger.warning("Conversation \(conversationId) not found in current conversation list")
        }
    }

    private func markConversationAsRead(_ conversation: Conversation) {
        Task { [weak self] in
            guard let self else { return }
            do {
                // Get or create the local state writer for this inbox
                // Wrap dictionary access in MainActor.run to prevent race conditions
                let localStateWriter: (any ConversationLocalStateWriterProtocol)? = await MainActor.run {
                    if let existingWriter = self.localStateWriters[conversation.inboxId] {
                        return existingWriter
                    }
                    return nil
                }

                let writer: any ConversationLocalStateWriterProtocol
                if let localStateWriter {
                    writer = localStateWriter
                } else {
                    // Create new writer outside of MainActor context
                    let messagingService = await session.messagingService(for: conversation.inboxId)
                    let newWriter = messagingService.conversationLocalStateWriter()

                    // Store it atomically on MainActor
                    await MainActor.run {
                        // Check again in case another task created it while we were waiting
                        if self.localStateWriters[conversation.inboxId] == nil {
                            self.localStateWriters[conversation.inboxId] = newWriter
                        }
                    }

                    writer = newWriter
                }

                try await writer.setUnread(false, for: conversation.id)
            } catch {
                Logger.warning("Failed marking conversation as read: \(error.localizedDescription)")
            }
        }
    }
}

extension ConversationsViewModel: NewConversationsViewModelDelegate {
    func newConversationsViewModel(
        _ viewModel: NewConversationViewModel,
        attemptedJoiningExistingConversationWithId conversationId: String
    ) {
        // stop showing new convo view
        newConversationViewModel = nil

        guard let conversation = conversations.first(where: { $0.id == conversationId }) else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.selectedConversation = conversation
        }
    }
}

extension ConversationsViewModel {
    static var mock: ConversationsViewModel {
        let client = ConvosClient.mock()
        return .init(
            session: client.session,
            conversationsRepository: client.session.conversationsRepository(for: .all),
            conversationsCountRepository: client.session.conversationsCountRepo(for: .all, kinds: .groups)
        )
    }
}
