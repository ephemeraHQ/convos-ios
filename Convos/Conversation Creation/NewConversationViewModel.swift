import Combine
import ConvosCore
import SwiftUI

protocol NewConversationsViewModelDelegate: AnyObject {
    func newConversationsViewModel(
        _ viewModel: NewConversationViewModel,
        attemptedJoiningExistingConversationWithId conversationId: String
    )
}

@Observable
class NewConversationViewModel: Identifiable {
    // MARK: - Public

    let session: any SessionManagerProtocol
    var conversationViewModel: ConversationViewModel?
    private weak var delegate: NewConversationsViewModelDelegate?
    private(set) var messagesTopBarTrailingItem: MessagesView.TopBarTrailingItem = .scan
    private(set) var shouldConfirmDeletingConversation: Bool = true
    private let startedWithFullscreenScanner: Bool
    private(set) var showingFullScreenScanner: Bool
    var presentingJoinConversationSheet: Bool = false
    var presentingInvalidInviteSheet: Bool = false
    private var initializationTask: Task<Void, Never>?

    private(set) var initializationError: Error?

    // MARK: - Private

    private var draftConversationComposer: (any DraftConversationComposerProtocol)? {
        didSet {
            setupObservations()
        }
    }
    private var messagingService: AnyMessagingService?
    private var newConversationTask: Task<Void, Never>?
    private var joinConversationTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    // MARK: - Init

    init(session: any SessionManagerProtocol, showScannerOnAppear: Bool = false, delegate: NewConversationsViewModelDelegate? = nil) {
        self.session = session
        self.startedWithFullscreenScanner = showScannerOnAppear
        self.showingFullScreenScanner = showScannerOnAppear
        self.delegate = delegate

        start()
    }

    deinit {
        Logger.info("🧹 deinit")
        initializationTask?.cancel()
        cancellables.removeAll()
        newConversationTask?.cancel()
        joinConversationTask?.cancel()
        conversationViewModel = nil
    }

    func start() {
        // Start async initialization
        initializationTask = Task { [weak self] in
            guard let self else { return }
            await self.initializeAsyncDependencies()
        }
    }

    @MainActor
    private func initializeAsyncDependencies() async {
        do {
            let messagingService = try await session.addInbox()
            self.messagingService = messagingService
            let draftConversationComposer = messagingService.draftConversationComposer()
            self.draftConversationComposer = draftConversationComposer
            let draftConversation = try draftConversationComposer.draftConversationRepository.fetchConversation() ?? .empty(
                id: draftConversationComposer.draftConversationRepository.conversationId
            )
            self.conversationViewModel = .init(
                conversation: draftConversation,
                session: session,
                draftConversationComposer: draftConversationComposer,
                myProfileRepository: messagingService.myProfileRepository()
            )
            self.conversationViewModel?.untitledConversationPlaceholder = "New convo"
            if showingFullScreenScanner {
                self.conversationViewModel?.showsInfoView = false
            }
            if !showingFullScreenScanner {
                try await draftConversationComposer.draftConversationWriter.createConversation()
            }
        } catch {
            Logger.error("Error initializing: \(error)")
            self.initializationError = error
        }
    }

    // MARK: - Actions

    func onScanInviteCode() {
        presentingJoinConversationSheet = true
    }

    func join(inviteUrlString: String) -> Bool {
        guard let inviteCode = inviteUrlString.inviteCodeFromJoinURL else {
            Logger.warning("Invalid invite URL")
            return false
        }
        Logger.info("Scanned inviteCode: \(inviteCode)")
        presentingJoinConversationSheet = false
        joinConversation(inviteCode: inviteCode)
        conversationViewModel?.showsInfoView = true
        return true
    }

    func deleteConversation() {
        Logger.info("Deleting conversation")
        newConversationTask?.cancel()
        joinConversationTask?.cancel()
        conversationViewModel = nil
        Task { [weak self] in
            guard let self else { return }
            guard let messagingService else { return }
            try await session.deleteInbox(for: messagingService)
            await draftConversationComposer?.draftConversationWriter.delete()
            self.messagingService = nil
        }
    }

    // MARK: - Private

    private func joinConversation(inviteCode: String) {
        joinConversationTask?.cancel()
        joinConversationTask = Task { [weak self] in
            guard let self else { return }
            do {
                // Request to join
                self.showingFullScreenScanner = false
                try await draftConversationComposer?.draftConversationWriter.requestToJoin(inviteCode: inviteCode)
            } catch ConversationStateMachineError.alreadyRedeemedInviteForConversation(let conversationId) {
                Logger.info("Invite already redeeemed, showing existing conversation...")
                await MainActor.run {
                    self.presentingJoinConversationSheet = false
                    self.delegate?.newConversationsViewModel(
                        self,
                        attemptedJoiningExistingConversationWithId: conversationId
                    )
                }
            } catch {
                Logger.error("Error joining new conversation: \(error.localizedDescription)")
                await MainActor.run {
                    if self.startedWithFullscreenScanner {
                        self.showingFullScreenScanner = true
                        self.conversationViewModel?.showsInfoView = false
                    }
                    self.presentingInvalidInviteSheet = true
                }
            }
        }
    }

    private func setupObservations() {
        cancellables.removeAll()

        guard let draftConversationComposer else {
            return
        }

        draftConversationComposer.draftConversationWriter.conversationIdPublisher
            .receive(on: DispatchQueue.main)
            .sink { conversationId in
                // Notify that active conversation has changed
                Logger.info("Active conversation changed: \(conversationId)")
                NotificationCenter.default.post(
                    name: .activeConversationChanged,
                    object: nil,
                    userInfo: ["conversationId": conversationId as Any]
                )
            }
            .store(in: &cancellables)

        Publishers.Merge(
            draftConversationComposer.draftConversationWriter.sentMessage.map { _ in () },
            draftConversationComposer.draftConversationRepository.messagesRepository
                .messagesPublisher
                .filter { !$0.isEmpty }
                .map { _ in () }
        )
        .eraseToAnyPublisher()
        .receive(on: DispatchQueue.main)
        .sink { [weak self] in
            guard let self else { return }
            messagesTopBarTrailingItem = .share
            shouldConfirmDeletingConversation = false
            conversationViewModel?.untitledConversationPlaceholder = "Untitled"
        }
        .store(in: &cancellables)
    }
}
