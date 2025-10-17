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
    var presentingInvalidInviteSheet: Bool = false {
        willSet {
            if !newValue {
                qrScannerViewModel.resetScanning()
            }
        }
    }
    var presentingFailedToJoinSheet: Bool = false

    // State tracking
    private(set) var isWaitingForInviteAcceptance: Bool = false
    private(set) var isValidatingInvite: Bool = false
    private(set) var isCreatingConversation: Bool = false
    private(set) var currentError: Error?
    private(set) var conversationState: ConversationStateMachine.State = .uninitialized

    // MARK: - Computed Properties

    /// Whether the conversation is in a loading/processing state
    var isProcessing: Bool {
        isCreatingConversation || isValidatingInvite || isWaitingForInviteAcceptance
    }

    /// Whether there is an active error
    var hasError: Bool {
        currentError != nil
    }

    /// Localized error message for display
    var errorMessage: String? {
        currentError?.localizedDescription
    }

    /// Whether the conversation is ready for use
    var isConversationReady: Bool {
        if case .ready = conversationState {
            return true
        }
        return false
    }

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

    func clearError() {
        currentError = nil
    }

    func retryAfterError() {
        guard let error = currentError else { return }
        Logger.info("Retrying after error: \(error.localizedDescription)")
        currentError = nil

        // If we were in the middle of joining, could potentially retry
        // For now, just clear the error and let the user try again
    }

    // MARK: - Private

    @MainActor
    private func handleJoinSuccess() {
        presentingJoinConversationSheet = false
        presentingInvalidInviteSheet = false
        conversationViewModel.showsInfoView = true
        showingFullScreenScanner = false
    }

    @MainActor
    private func handleJoinError(_ error: Error) {
        withAnimation {
            if startedWithFullscreenScanner {
                showingFullScreenScanner = true
                conversationViewModel.showsInfoView = false
            }

            // Determine which sheet to present based on error type
            if let stateMachineError = error as? ConversationStateMachineError {
                switch stateMachineError {
                case .invalidInviteCodeFormat, .inviteExpired:
                    presentingInvalidInviteSheet = true
                case .timedOut:
                    presentingFailedToJoinSheet = true
                case .failedFindingConversation, .failedVerifyingSignature, .stateMachineError:
                    presentingInvalidInviteSheet = true
                }
            } else {
                presentingInvalidInviteSheet = true
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
            isValidatingInvite = false
            isCreatingConversation = false
            messagesTopBarTrailingItemEnabled = false
            messagesBottomBarEnabled = false
            currentError = nil

        case .creating:
            isCreatingConversation = true
            isValidatingInvite = false
            isWaitingForInviteAcceptance = false
            currentError = nil

        case .validating:
            isValidatingInvite = true
            isCreatingConversation = false
            isWaitingForInviteAcceptance = false
            currentError = nil

        case .validated:
            isValidatingInvite = false
            isCreatingConversation = false
            isWaitingForInviteAcceptance = false
            currentError = nil

        case .joining:
            // This is the waiting state - user is waiting for inviter to accept
            messagesTopBarTrailingItemEnabled = false
            messagesTopBarTrailingItem = .share
            messagesBottomBarEnabled = false
            isWaitingForInviteAcceptance = true
            shouldConfirmDeletingConversation = false
            conversationViewModel.untitledConversationPlaceholder = "Untitled"
            isValidatingInvite = false
            isCreatingConversation = false
            currentError = nil
            Logger.info("Waiting for invite acceptance...")

        case .ready:
            messagesTopBarTrailingItemEnabled = true
            messagesBottomBarEnabled = true
            isWaitingForInviteAcceptance = false
            isValidatingInvite = false
            isCreatingConversation = false
            currentError = nil
            Logger.info("Conversation ready!")

        case .deleting:
            isWaitingForInviteAcceptance = false
            isValidatingInvite = false
            isCreatingConversation = false
            currentError = nil

        case .error(let error):
            isWaitingForInviteAcceptance = false
            isValidatingInvite = false
            isCreatingConversation = false
            currentError = error
            Logger.error("Conversation state error: \(error.localizedDescription)")
            // Handle specific error types
            handleError(error)
        }
    }

    @MainActor
    private func handleError(_ error: Error) {
        // Map state machine errors to appropriate UI states
        if let stateMachineError = error as? ConversationStateMachineError {
            switch stateMachineError {
            case .invalidInviteCodeFormat, .inviteExpired, .failedVerifyingSignature:
                presentingInvalidInviteSheet = true
            case .failedFindingConversation, .stateMachineError, .timedOut:
                // Generic error - could show a different alert
                presentingFailedToJoinSheet = true
            }
        } else {
            presentingFailedToJoinSheet = true
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
