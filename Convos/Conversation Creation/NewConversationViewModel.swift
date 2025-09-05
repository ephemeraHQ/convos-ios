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
    private(set) var showScannerOnAppear: Bool
    var presentingJoinConversationSheet: Bool = false
    private var initializationTask: Task<Void, Never>?
    private var prefilledInviteCode: String?

    // Error handling
    var joinError: String?
    var presentingJoinError: Bool = false

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
        self.showScannerOnAppear = showScannerOnAppear
        self.delegate = delegate
        self.prefilledInviteCode = prefilledInviteCode

        // Start async initialization
        initializationTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.initializeAsyncDependencies()
            } catch {
                Logger.error("Error initializing: \(error)")
            }
        }
    }

    deinit {
        Logger.info("🧹 deinit")
        initializationTask?.cancel()
        cancellables.removeAll()
        newConversationTask?.cancel()
        joinConversationTask?.cancel()
        conversationViewModel = nil
    }

    @MainActor
    private func initializeAsyncDependencies() async throws {
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
        } else if showScannerOnAppear {
            // Only show scanner when manually joining (no prefilled code)
            self.conversationViewModel?.showsInfoView = false
        } else {
            // Create new conversation when not joining
            try await draftConversationComposer.draftConversationWriter.createConversation()
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
        let inviteCode: String

        // Try to extract invite code from URL first
        if let extractedCode = inviteUrlString.inviteCodeFromJoinURL {
            inviteCode = extractedCode
        } else {
            // If it's not a valid URL, treat as direct invite code
            // Only accept if it looks like a valid invite code (no spaces, reasonable length)
            guard !inviteUrlString.contains(" "), inviteUrlString.count >= 8 else {
                Logger.warning("Invalid invite code format: \(inviteUrlString)")
                return false
            }
            inviteCode = inviteUrlString
        }

        Logger.info("Processing inviteCode: \(inviteCode)")
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
                try await draftConversationComposer?.draftConversationWriter.requestToJoin(inviteCode: inviteCode)
                Logger.info("Successfully joined conversation")
            } catch {
                Logger.error("Error joining conversation: \(error.localizedDescription)")
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
