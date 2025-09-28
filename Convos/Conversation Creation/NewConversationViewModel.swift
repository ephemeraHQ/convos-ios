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
    private(set) var messagesTopBarTrailingItem: MessagesView.TopBarTrailingItem = .scan
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
        self.qrScannerViewModel = QRScannerViewModel()
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
            myProfileRepository: draftConversationComposer.draftConversationRepository.myProfileRepository
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

    func joinConversation(inviteCode: String) {
        joinConversationTask?.cancel()
        joinConversationTask = Task { [weak self] in
            guard let self else { return }

            // wait for init
            await initializationTask?.value

            guard !Task.isCancelled else { return }

            do {
                // Request to join
                try await draftConversationComposer.draftConversationWriter.joinConversation(inviteCode: inviteCode)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.presentingJoinConversationSheet = false
                    self.presentingInvalidInviteSheet = false
                    self.conversationViewModel.showsInfoView = true
                    self.showingFullScreenScanner = false
                }
            } catch {
                Logger.error("Error joining new conversation: \(error.localizedDescription)")
                guard !Task.isCancelled else { return }
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

    func deleteConversation() {
        Logger.info("Deleting conversation")
        newConversationTask?.cancel()
        joinConversationTask?.cancel()
        Task { [weak self] in
            guard let self else { return }
            await draftConversationComposer.draftConversationWriter.delete()
        }
    }

    // MARK: - Private

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
