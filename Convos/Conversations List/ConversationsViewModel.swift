import Combine
import ConvosCore
import Foundation
import Observation

@Observable
class SelectableConversationViewModelType {
    var selectedConversationViewModel: ConversationViewModel?
}

@Observable
final class ConversationsViewModel: SelectableConversationViewModelType {
    // MARK: - Public

    var selectedConversation: Conversation? {
        didSet {
            if let selectedConversation {
                selectedConversationViewModel = conversationViewModel(for: selectedConversation)
            } else {
                selectedConversationViewModel = nil
            }
        }
    }
    var newConversationViewModel: NewConversationViewModel?
    var presentingExplodeInfo: Bool = false
    private(set) var conversations: [Conversation] = []
    private(set) var conversationsCount: Int = 0

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
        super.init()
        observe()
    }

    deinit {
        if let leftConversationObserver {
            NotificationCenter.default.removeObserver(leftConversationObserver)
        }
        cancellables.removeAll()
    }

    func onStartConvo() {
        newConversationViewModel = .init(session: session)
    }

    func onJoinConvo() {
        newConversationViewModel = .init(session: session, showScannerOnAppear: true)
    }

    func deleteAllAccounts() {
        do {
            try session.deleteAllAccounts()
        } catch {
            Logger.error("Error deleting all accounts: \(error)")
        }
    }

    func leave(conversation: Conversation) {
        do {
            try session.deleteAccount(inboxId: conversation.inboxId)
            NotificationCenter.default.post(
                name: .leftConversationNotification,
                object: nil,
                userInfo: ["inboxId": conversation.inboxId, "conversationId": conversation.id]
            )
        } catch {
            Logger.error("Error leaving convo: \(error.localizedDescription)")
        }
    }

    func conversationViewModel(for conversation: Conversation) -> ConversationViewModel {
        let messagingService = session.messagingService(for: conversation.inboxId)
        return .init(
            conversation: conversation,
            session: session,
            myProfileWriter: messagingService.myProfileWriter(),
            myProfileRepository: messagingService.myProfileRepository(),
            conversationRepository: messagingService.conversationRepository(for: conversation.id),
            messagesRepository: messagingService.messagesRepository(for: conversation.id),
            outgoingMessageWriter: messagingService.messageWriter(for: conversation.id),
            consentWriter: messagingService.conversationConsentWriter(),
            localStateWriter: messagingService.conversationLocalStateWriter(),
            metadataWriter: messagingService.groupMetadataWriter(),
            inviteRepository: messagingService.inviteRepository(for: conversation.id)
        )
    }

    private func observe() {
        leftConversationObserver = NotificationCenter.default
            .addObserver(forName: .leftConversationNotification, object: nil, queue: .main) { [weak self] notification in
                guard let self else { return }
                guard let conversationId: String = notification.userInfo?["conversationId"] as? String else {
                    return
                }
                Logger.info("📢 Left conversation notification received for conversation: \(conversationId)")
                if selectedConversation?.id == conversationId {
                    selectedConversation = nil
                }
                if newConversationViewModel?.selectedConversationViewModel?.conversation.id == conversationId {
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
