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
    let allowsDismissingScanner: Bool
    private let autoCreateConversation: Bool
    private(set) var showingFullScreenScanner: Bool
    var presentingJoinConversationSheet: Bool = false
    var presentingInvalidInviteSheet: Bool = false
    var presentingFailedToJoinSheet: Bool = false
    var presentingInviterOfflineSheet: Bool = false
    var isJoiningConversation: Bool = false
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
    private var joinConversationTask: Task<Void, Error>?
    private var cancellables: Set<AnyCancellable> = []

    // MARK: - Init

    init(
        session: any SessionManagerProtocol,
        autoCreateConversation: Bool = false,
        showingFullScreenScanner: Bool = false,
        allowsDismissingScanner: Bool = true,
        delegate: NewConversationsViewModelDelegate? = nil
    ) {
        self.session = session
        self.autoCreateConversation = autoCreateConversation
        self.startedWithFullscreenScanner = showingFullScreenScanner
        self.showingFullScreenScanner = showingFullScreenScanner
        self.allowsDismissingScanner = allowsDismissingScanner
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
        initializationTask?.cancel()
        initializationError = nil
        initializationTask = Task { [weak self] in
            guard let self else { return }
            await self.initializeAsyncDependencies()
        }
    }

    @MainActor
    private func initializeAsyncDependencies() async {
        do {
            let messagingService: AnyMessagingService
            if let existing = self.messagingService {
                messagingService = existing
            } else {
                messagingService = try await session.addInbox()
                self.messagingService = messagingService
            }
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
            if autoCreateConversation {
                try await draftConversationComposer.draftConversationWriter.createConversation()
            }
        } catch is CancellationError {
            return
        } catch {
            Logger.error("Error initializing: \(error)")
            withAnimation {
                self.initializationError = error
                self.conversationViewModel = nil
            }
        }
    }

    // MARK: - Actions

    func onScanInviteCode() {
        presentingJoinConversationSheet = true
    }

    func join(inviteUrlString: String) -> Bool {
        // Clear any previous errors when starting a new join attempt
        presentingInvalidInviteSheet = false

        let inviteCode: String

        // Try to extract invite code from URL first
        if let url = URL(string: inviteUrlString), let extractedCode = url.convosInviteCode {
            inviteCode = extractedCode
        } else {
            // If it's not a valid URL, treat as direct invite code
            // Only accept if it looks like a valid invite code (no spaces, reasonable length)
            guard !inviteUrlString.contains(" "), inviteUrlString.count >= 8 else {
                Logger.warning("Invalid invite code format: \(inviteUrlString)")
                presentingInvalidInviteSheet = true
                return false
            }
            inviteCode = inviteUrlString
        }

        Logger.info("Processing inviteCode")
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

            // wait for init
            await initializationTask?.value

            guard let draftConversationComposer else {
                Logger.error("Join attempted before initialization finished")
                guard !Task.isCancelled else { return }
                await MainActor.run { self.presentingFailedToJoinSheet = true }
                return
            }

            if let existingConversationId = await draftConversationComposer.draftConversationWriter.checkIfAlreadyJoined(inviteCode: inviteCode) {
                Logger.info("Invite already redeeemed, showing existing conversation... conversationId: \(existingConversationId)")
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.presentingJoinConversationSheet = false
                    self.delegate?.newConversationsViewModel(
                        self,
                        attemptedJoiningExistingConversationWithId: existingConversationId
                    )
                }
                return
            }

            guard !Task.isCancelled else { return }

            do {
                // Show loading state and hide scanner
                await MainActor.run {
                    self.showingFullScreenScanner = false
                    self.isJoiningConversation = true
                }

                // Request to join
                try await draftConversationComposer.draftConversationWriter.requestToJoin(inviteCode: inviteCode)

                // Success - hide loading state
                await MainActor.run {
                    self.isJoiningConversation = false
                }
            } catch ConversationStateMachineError.alreadyRedeemedInviteForConversation(let conversationId) {
                Logger.info("Invite already redeeemed, showing existing conversation...")
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.isJoiningConversation = false
                    self.presentingJoinConversationSheet = false
                    self.delegate?.newConversationsViewModel(
                        self,
                        attemptedJoiningExistingConversationWithId: conversationId
                    )
                }
            } catch ConversationStateMachineError.timedOut {
                Logger.info("Join request timed out - inviter may be offline")
                await MainActor.run {
                    self.isJoiningConversation = false
                    withAnimation {
                        if self.startedWithFullscreenScanner {
                            self.showingFullScreenScanner = true
                            self.conversationViewModel?.showsInfoView = false
                        }
                        self.presentingInviterOfflineSheet = true
                    }
                }
            } catch {
                Logger.error("Error joining new conversation: \(error.localizedDescription)")
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.isJoiningConversation = false
                    withAnimation {
                        if self.startedWithFullscreenScanner {
                            self.showingFullScreenScanner = true
                            self.conversationViewModel?.showsInfoView = false
                        }
                        self.presentingInvalidInviteSheet = true
                    }
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
