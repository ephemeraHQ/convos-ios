import Combine
import Foundation
import Observation

@Observable
class SelectableConversationViewModelType {
    var selectedConversation: ConversationViewModel?
}

@Observable
final class ConversationsViewModel: SelectableConversationViewModelType {
    private(set) var conversations: [Conversation]
    private(set) var conversationsCount: Int = 0

    var newConversationViewModel: NewConversationViewModel?

    var pinnedConversations: [Conversation] {
        conversations.filter { $0.isPinned }.filter { $0.kind == .group } // @jarodl temporarily filtering out dms
    }
    var unpinnedConversations: [Conversation] {
        conversations.filter { !$0.isPinned }.filter { $0.kind == .group } // @jarodl temporarily filtering out dms
    }

    private let session: any SessionManagerProtocol
    private let conversationsRepository: any ConversationsRepositoryProtocol
    private let conversationsCountRepository: any ConversationsCountRepositoryProtocol
    private var cancellables: Set<AnyCancellable> = .init()

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
