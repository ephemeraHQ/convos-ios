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
class NewConversationViewModel: SelectableConversationViewModelType, Identifiable {
    override var selectedConversationViewModel: ConversationViewModel? {
        get {
            conversationViewModel
        }
        set {
            conversationViewModel = newValue
        }
    }

    // MARK: - Public

    let session: any SessionManagerProtocol
    var conversationViewModel: ConversationViewModel?
    private weak var delegate: NewConversationsViewModelDelegate?
    private(set) var messagesTopBarTrailingItem: MessagesView.TopBarTrailingItem = .scan
    private(set) var shouldConfirmDeletingConversation: Bool = true
    private(set) var showScannerOnAppear: Bool
    var presentingJoinConversationSheet: Bool = false

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
        self.showScannerOnAppear = showScannerOnAppear
        self.delegate = delegate
        super.init()
    }

    deinit {
        Logger.info("🧹 deinit")
        cancellables.removeAll()
        newConversationTask?.cancel()
        joinConversationTask?.cancel()
        conversationViewModel = nil
    }

    // MARK: - Actions

    func onScanInviteCode() {
        presentingJoinConversationSheet = true
    }

    func newConversation() {
        guard messagingService == nil else { return }
        newConversationTask?.cancel()
        newConversationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let messagingService = try session.addInbox()
                self.messagingService = messagingService
                guard !Task.isCancelled else { return }
                let draftConversationComposer = messagingService.draftConversationComposer()
                self.draftConversationComposer = draftConversationComposer
                self.conversationViewModel = try conversationViewModel(
                    for: messagingService,
                    from: draftConversationComposer
                )
                guard !Task.isCancelled else { return }
                try await draftConversationComposer.draftConversationWriter.createConversation()
            } catch {
                Logger.error("Error starting new conversation: \(error.localizedDescription)")
            }
        }
    }

    func join(inviteUrlString: String) -> Bool {
        guard let inviteCode = inviteUrlString.inviteCodeFromJoinURL else {
            Logger.warning("Invalid invite URL")
            return false
        }
        Logger.info("Scanned inviteCode: \(inviteCode)")
        presentingJoinConversationSheet = false
        joinConversation(inviteCode: inviteCode)
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
            try session.deleteInbox(for: messagingService)
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
                // Ensure we have a messaging service
                if self.messagingService == nil {
                    Logger.info("No messaging service found, starting one while joining conversation...")
                    let messagingService = try session.addInbox()
                    self.messagingService = messagingService
                }

                guard let messagingService else {
                    Logger.error("Failed adding account while joining conversation")
                    return
                }

                // Ensure we have a draft conversation composer
                if self.draftConversationComposer == nil {
                    Logger.info("Setting up draft composer for joining conversation...")
                    let draftConversationComposer = messagingService.draftConversationComposer()
                    self.draftConversationComposer = draftConversationComposer
                }

                guard let draftConversationComposer else {
                    Logger.error("Failed getting conversation composer while joining conversation")
                    return
                }

                // Ensure we have a conversation view model
                if self.conversationViewModel == nil {
                    Logger.info("ConversationViewModel is `nil`... creating a new one.")
                    self.conversationViewModel = try conversationViewModel(
                        for: messagingService,
                        from: draftConversationComposer
                    )
                }

                // Request to join
                do {
                    try await draftConversationComposer.draftConversationWriter.requestToJoin(inviteCode: inviteCode)
                } catch ConversationStateMachineError.alreadyRedeemedInviteForConversation(let conversationId) {
                    Logger.info("Invite already redeeemed, showing existing conversation...")
                    presentingJoinConversationSheet = false
                    delegate?.newConversationsViewModel(
                        self,
                        attemptedJoiningExistingConversationWithId: conversationId
                    )
                }
            } catch {
                Logger.error("Error joining new conversation: \(error.localizedDescription)")
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

    func conversationViewModel(
        for messagingService: AnyMessagingService,
        from draftConversationComposer: any DraftConversationComposerProtocol
    ) throws -> ConversationViewModel {
        let draftConversation = try draftConversationComposer.draftConversationRepository.fetchConversation() ?? .empty(
            id: draftConversationComposer.draftConversationRepository.conversationId
        )
        let viewModel: ConversationViewModel = .init(
            conversation: draftConversation,
            session: session,
            myProfileWriter: draftConversationComposer.myProfileWriter,
            myProfileRepository: messagingService.myProfileRepository(),
            conversationRepository: draftConversationComposer.draftConversationRepository,
            messagesRepository: draftConversationComposer.draftConversationRepository.messagesRepository,
            outgoingMessageWriter: draftConversationComposer.draftConversationWriter,
            consentWriter: draftConversationComposer.conversationConsentWriter,
            localStateWriter: draftConversationComposer.conversationLocalStateWriter,
            metadataWriter: draftConversationComposer.conversationMetadataWriter,
            inviteRepository: draftConversationComposer.draftConversationRepository.inviteRepository
        )
        viewModel.untitledConversationPlaceholder = "New convo"
        return viewModel
    }
}
