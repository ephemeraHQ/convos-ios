import Combine
import ConvosCore
import SwiftUI

protocol NewConversationsViewModelDelegate: AnyObject {
    func newConversationsViewModel(
        _ viewModel: NewConversationViewModel,
        attemptedJoiningExistingConversationWithId conversationId: String
    )
}

// MARK: - Error Types

struct IdentifiableError: Identifiable {
    let id: UUID = UUID()
    let error: DisplayError

    var title: String { error.title }
    var description: String { error.description }
}

struct GenericDisplayError: DisplayError {
    let title: String
    let description: String
}

@Observable
class NewConversationViewModel: Identifiable {
    // MARK: - Public

    let session: any SessionManagerProtocol
    let conversationViewModel: ConversationViewModel
    let qrScannerViewModel: QRScannerViewModel
    private weak var delegate: NewConversationsViewModelDelegate?
    private(set) var messagesTopBarTrailingItem: MessagesViewTopBarTrailingItem = .scan
    private(set) var messagesTopBarTrailingItemEnabled: Bool = false
    private(set) var messagesBottomBarEnabled: Bool = false
    private(set) var shouldConfirmDeletingConversation: Bool = true
    private let startedWithFullscreenScanner: Bool
    let allowsDismissingScanner: Bool
    private let autoCreateConversation: Bool
    private(set) var showingFullScreenScanner: Bool
    var presentingJoinConversationSheet: Bool = false
    var displayError: IdentifiableError? {
        didSet {
            qrScannerViewModel.presentingInvalidInviteSheet = displayError != nil
            // Reset scan timer when dismissing the error sheet to allow immediate re-scanning
            if oldValue != nil && displayError == nil {
                qrScannerViewModel.resetScanTimer()
            }
        }
    }

    // State tracking
    private(set) var isWaitingForInviteAcceptance: Bool = false
    private(set) var isCreatingConversation: Bool = false
    private(set) var currentError: Error?
    private(set) var conversationState: ConversationStateMachine.State = .uninitialized

    // MARK: - Private

    private let conversationStateManager: any ConversationStateManagerProtocol
    private var newConversationTask: Task<Void, Error>?
    private var joinConversationTask: Task<Void, Error>?
    private var cancellables: Set<AnyCancellable> = []
    private var stateObserverHandle: ConversationStateObserverHandle?

    // MARK: - Init

    static func create(
        session: any SessionManagerProtocol,
        autoCreateConversation: Bool = false,
        showingFullScreenScanner: Bool = false,
        allowsDismissingScanner: Bool = true,
        delegate: NewConversationsViewModelDelegate? = nil
    ) async -> NewConversationViewModel {
        let messagingService = await session.addInbox()
        return NewConversationViewModel(
            session: session,
            messagingService: messagingService,
            autoCreateConversation: autoCreateConversation,
            showingFullScreenScanner: showingFullScreenScanner,
            allowsDismissingScanner: allowsDismissingScanner,
            delegate: delegate
        )
    }

    /// Internal initializer for previews and tests
    internal init(
        session: any SessionManagerProtocol,
        messagingService: AnyMessagingService,
        autoCreateConversation: Bool = false,
        showingFullScreenScanner: Bool = false,
        allowsDismissingScanner: Bool = true,
        delegate: NewConversationsViewModelDelegate? = nil
    ) {
        self.session = session
        self.qrScannerViewModel = QRScannerViewModel()
        self.autoCreateConversation = autoCreateConversation
        self.startedWithFullscreenScanner = showingFullScreenScanner
        self.showingFullScreenScanner = showingFullScreenScanner
        self.allowsDismissingScanner = allowsDismissingScanner
        self.delegate = delegate

        let conversationStateManager = messagingService.conversationStateManager()
        self.conversationStateManager = conversationStateManager
        let draftConversation: Conversation = .empty(
            id: conversationStateManager.draftConversationRepository.conversationId
        )
        self.conversationViewModel = .init(
            conversation: draftConversation,
            session: session,
            conversationStateManager: conversationStateManager,
            myProfileRepository: conversationStateManager.draftConversationRepository.myProfileRepository
        )
        setupObservations()
        setupStateObservation()
        self.conversationViewModel.untitledConversationPlaceholder = "New convo"
        if showingFullScreenScanner {
            self.conversationViewModel.showsInfoView = false
        }
        if autoCreateConversation {
            newConversationTask = Task { [weak self] in
                guard let self else { return }
                guard !Task.isCancelled else { return }
                do {
                    try await conversationStateManager.createConversation()
                } catch {
                    Logger.error("Error auto-creating conversation: \(error.localizedDescription)")
                    guard !Task.isCancelled else { return }
                    await handleCreationError(error)
                }
            }
        }
    }

    deinit {
        Logger.info("deinit")
        cancellables.removeAll()
        newConversationTask?.cancel()
        joinConversationTask?.cancel()
        stateObserverHandle?.cancel()
    }

    // MARK: - Actions

    func onScanInviteCode() {
        presentingJoinConversationSheet = true
    }

    func joinConversation(inviteCode: String) {
        joinConversationTask?.cancel()
        joinConversationTask = Task { [weak self] in
            guard let self else { return }
            guard !Task.isCancelled else { return }
            do {
                // Request to join - this will trigger state changes through the observer
                try await conversationStateManager.joinConversation(inviteCode: inviteCode)
                guard !Task.isCancelled else { return }

                await handleJoinSuccess()
            } catch {
                Logger.error("Error joining new conversation: \(error.localizedDescription)")
                guard !Task.isCancelled else { return }
                await handleJoinError(error)
            }
        }
    }

    func deleteConversation() {
        Logger.info("Deleting conversation")
        newConversationTask?.cancel()
        joinConversationTask?.cancel()
        Task { [weak self] in
            guard let self else { return }
            do {
                try await conversationStateManager.delete()
            } catch {
                Logger.error("Failed deleting conversation: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Private

    @MainActor
    private func handleJoinSuccess() {
        presentingJoinConversationSheet = false
        displayError = nil
        conversationViewModel.showsInfoView = true
    }

    @MainActor
    private func handleJoinError(_ error: Error) {
        withAnimation {
            qrScannerViewModel.resetScanning()

            if startedWithFullscreenScanner {
                showingFullScreenScanner = true
                conversationViewModel.showsInfoView = false
            }

            // Set the display error
            if let displayError = error as? DisplayError {
                self.displayError = IdentifiableError(error: displayError)
            } else {
                // Fallback for non-DisplayError errors
                self.displayError = IdentifiableError(error: GenericDisplayError(
                    title: "Failed joining",
                    description: "Please try again."
                ))
            }
        }
    }

    @MainActor
    private func handleCreationError(_ error: Error) {
        currentError = error
        isCreatingConversation = false
    }

    private func setupStateObservation() {
        stateObserverHandle = conversationStateManager.observeState { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                self.handleStateChange(state)
            }
        }
    }

    @MainActor
    private func handleStateChange(_ state: ConversationStateMachine.State) {
        conversationState = state

        switch state {
        case .uninitialized:
            isWaitingForInviteAcceptance = false
            isCreatingConversation = false
            messagesTopBarTrailingItemEnabled = false
            messagesBottomBarEnabled = false
            currentError = nil
            qrScannerViewModel.resetScanning()

        case .creating:
            isCreatingConversation = true
            isWaitingForInviteAcceptance = false
            currentError = nil

        case .validating:
            isCreatingConversation = false
            isWaitingForInviteAcceptance = false
            currentError = nil

        case .validated:
            isCreatingConversation = false
            isWaitingForInviteAcceptance = false
            currentError = nil
            showingFullScreenScanner = false

        case .joining:
            // This is the waiting state - user is waiting for inviter to accept
            messagesTopBarTrailingItemEnabled = false
            messagesTopBarTrailingItem = .share
            messagesBottomBarEnabled = false
            isWaitingForInviteAcceptance = true
            shouldConfirmDeletingConversation = false
            conversationViewModel.untitledConversationPlaceholder = "Untitled"
            isCreatingConversation = false
            currentError = nil
            Logger.info("Waiting for invite acceptance...")

        case .ready:
            messagesTopBarTrailingItemEnabled = true
            messagesBottomBarEnabled = true
            isWaitingForInviteAcceptance = false
            isCreatingConversation = false
            currentError = nil
            Logger.info("Conversation ready!")

        case .deleting:
            isWaitingForInviteAcceptance = false
            isCreatingConversation = false
            currentError = nil

        case .error(let error):
            qrScannerViewModel.resetScanning()
            isWaitingForInviteAcceptance = false
            isCreatingConversation = false
            currentError = error
            Logger.error("Conversation state error: \(error.localizedDescription)")
            // Handle specific error types
            handleError(error)
        }
    }

    @MainActor
    private func handleError(_ error: Error) {
        // Set the display error
        if let displayError = error as? DisplayError {
            self.displayError = IdentifiableError(error: displayError)
        } else {
            // Fallback for non-DisplayError errors
            self.displayError = IdentifiableError(error: GenericDisplayError(
                title: "Failed creating",
                description: "Please try again."
            ))
        }

        if startedWithFullscreenScanner {
            showingFullScreenScanner = true
            conversationViewModel.showsInfoView = false
        }
    }

    private func setupObservations() {
        cancellables.removeAll()

        conversationStateManager.conversationIdPublisher
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
            conversationStateManager.sentMessage.map { _ in () },
            conversationStateManager.draftConversationRepository.messagesRepository
                .messagesPublisher
                .filter { $0.contains { $0.base.content.showsInMessagesList } }
                .map { _ in () }
        )
        .eraseToAnyPublisher()
        .receive(on: DispatchQueue.main)
        .sink { [weak self] in
            guard let self else { return }
            messagesTopBarTrailingItem = .share
            shouldConfirmDeletingConversation = false
            conversationViewModel.untitledConversationPlaceholder = "Untitled"
        }
        .store(in: &cancellables)
    }
}
