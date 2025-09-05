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
    private var prefilledInviteCode: String?

    // Error handling
    var joinError: String?
    var presentingJoinError: Bool = false

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

    init(session: any SessionManagerProtocol, showScannerOnAppear: Bool = false, delegate: NewConversationsViewModelDelegate? = nil, prefilledInviteCode: String? = nil) {
        self.session = session
        self.startedWithFullscreenScanner = showScannerOnAppear
        self.showingFullScreenScanner = showScannerOnAppear
        self.delegate = delegate
        self.prefilledInviteCode = prefilledInviteCode

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

            // Handle prefilled invite code (from deep links)
            if let prefilledInviteCode {
                self.conversationViewModel?.showsInfoView = false
                let success = joinWithErrorHandling(inviteUrlString: prefilledInviteCode)
                if !success {
                    Logger.warning("Failed to join with prefilled invite code: \(prefilledInviteCode)")
                    return
                }
            } else if showingFullScreenScanner {
                // Only show scanner when manually joining (no prefilled code)
                self.conversationViewModel?.showsInfoView = false
            } else {
                // Create new conversation when not joining
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

    func dismissJoinError() {
        joinError = nil
        presentingJoinError = false
    }

    func join(inviteUrlString: String) -> Bool {
        // Clear any previous errors when starting a new join attempt
        joinError = nil
        presentingJoinError = false

        let inviteCode: String

        // Extract invite code from URL, or use the string directly
        inviteCode = inviteUrlString.inviteCodeFromJoinURL ?? inviteUrlString

        Logger.info("Processing inviteCode")
        presentingJoinConversationSheet = false
        joinConversation(inviteCode: inviteCode)
        conversationViewModel?.showsInfoView = true
        return true
    }

    func joinWithErrorHandling(inviteUrlString: String) -> Bool {
        let success = join(inviteUrlString: inviteUrlString)
        if !success {
            joinError = "Invalid invite code. Please check the link and try again."
            presentingJoinError = true
        }
        return success
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

            // First check if we've already joined this conversation
            if let existingConversationId = await draftConversationComposer?.draftConversationWriter.checkIfAlreadyJoined(inviteCode: inviteCode) {
                Logger.info("Invite already redeeemed, showing existing conversation... conversationId: \(existingConversationId)")
                await MainActor.run {
                    self.presentingJoinConversationSheet = false
                    self.delegate?.newConversationsViewModel(
                        self,
                        attemptedJoiningExistingConversationWithId: existingConversationId
                    )
                }
                return
            }

            // If not already joined, proceed with joining
            do {
                self.showingFullScreenScanner = false
                try await draftConversationComposer?.draftConversationWriter.requestToJoin(inviteCode: inviteCode)
                Logger.info("Successfully joined conversation")
                await MainActor.run {
                    // Clear any previous errors on success
                    self.joinError = nil
                    self.presentingJoinError = false
                    self.conversationViewModel?.showsInfoView = true
                }
            } catch {
                Logger.error("Error joining conversation: \(error.localizedDescription)")
                await MainActor.run {
                    self.joinError = error.localizedDescription.isEmpty ?
                        "Failed to join conversation. Please check your connection and try again." :
                        error.localizedDescription
                    self.presentingJoinError = true

                    if self.startedWithFullscreenScanner {
                        self.showingFullScreenScanner = true
                        self.conversationViewModel?.showsInfoView = false
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
