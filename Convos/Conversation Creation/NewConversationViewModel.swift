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
    private var initializationTask: Task<Void, Never>?
    private(set) var initializationError: Error?

    // MARK: - Private

    private let draftConversationComposer: any DraftConversationComposerProtocol
    private let messagingService: AnyMessagingService
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

        self.messagingService = session.messagingService
        let draftConversationComposer = messagingService.draftConversationComposer()
        self.draftConversationComposer = draftConversationComposer
        let draftConversation: Conversation = .empty(
            id: draftConversationComposer.draftConversationRepository.conversationId
        )
        self.conversationViewModel = .init(
            conversation: draftConversation,
            session: session,
            draftConversationComposer: draftConversationComposer,
            myProfileRepository: messagingService.myProfileRepository()
        )
        setupObservations()
        self.conversationViewModel.untitledConversationPlaceholder = "New convo"
        if showingFullScreenScanner {
            self.conversationViewModel.showsInfoView = false
        }
        if autoCreateConversation {
            Task {
                try await draftConversationComposer.draftConversationWriter.createConversation()
            }
        }
    }

    deinit {
        Logger.info("deinit")
        cancellables.removeAll()
        newConversationTask?.cancel()
        joinConversationTask?.cancel()
    }

    // MARK: - Actions

    func onScanInviteCode() {
        presentingJoinConversationSheet = true
    }

    func validate(inviteUrlString: String) -> String? {
        let inviteCode: String
        // Try to extract invite code from URL first
        if let url = URL(string: inviteUrlString), let extractedCode = url.convosInviteCode {
            inviteCode = extractedCode
        } else if !inviteUrlString.contains(" "), inviteUrlString.count >= 8 {
            inviteCode = inviteUrlString
        } else {
            return nil
        }
        Logger.info("Validated invite code: \(inviteCode)")
        return inviteCode
    }

    func validateAndJoin(inviteUrlString: String) -> Bool {
        // Clear any previous errors when starting a new join attempt
        presentingInvalidInviteSheet = false

        let validatedInviteCode = validate(inviteUrlString: inviteUrlString)
        guard let validatedInviteCode else {
            Logger.warning("Invalid invite code format: \(inviteUrlString)")
            presentingInvalidInviteSheet = true
            return false
        }

        presentingJoinConversationSheet = false
        joinConversation(inviteCode: validatedInviteCode)
        conversationViewModel.showsInfoView = true
        return true
    }

    func deleteConversation() {
        Logger.info("Deleting conversation")
        newConversationTask?.cancel()
        joinConversationTask?.cancel()
        Task { [weak self] in
            guard let self else { return }
//            try await session.deleteInbox(for: messagingService)
            await draftConversationComposer.draftConversationWriter.delete()
//            self.messagingService = nil
        }
    }

    // MARK: - Private

    func joinConversation(inviteCode: String) {
        joinConversationTask?.cancel()
        joinConversationTask = Task { [weak self] in
            guard let self else { return }

            // wait for init
            await initializationTask?.value

            do {
                // Request to join
                await MainActor.run { self.showingFullScreenScanner = false }
                try await draftConversationComposer.draftConversationWriter.requestToJoin(inviteCode: inviteCode)
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
                    withAnimation {
                        if self.startedWithFullscreenScanner {
                            self.showingFullScreenScanner = true
                            self.conversationViewModel.showsInfoView = false
                        }
                        self.presentingInvalidInviteSheet = true
                    }
                }
            }
        }
    }

    private func setupObservations() {
        cancellables.removeAll()

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
            conversationViewModel.untitledConversationPlaceholder = "Untitled"
        }
        .store(in: &cancellables)
    }
}
