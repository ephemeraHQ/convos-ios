import Combine
import SwiftUI

@Observable
class NewConversationViewModel: Identifiable {
    // MARK: - Public

    let session: any SessionManagerProtocol
    var conversationViewModel: ConversationViewModel?
    private(set) var messagesTopBarTrailingItem: MessagesTopBar.TrailingItem = .scan
    private(set) var shouldConfirmDeletingConversation: Bool = true
    private(set) var showScannerOnAppear: Bool

    // MARK: - Private

    private var draftConversationComposer: (any DraftConversationComposerProtocol)? {
        didSet {
            setupObservations()
        }
    }
    private var addAccountResult: AddAccountResultType?
    private var newConversationTask: Task<Void, Never>?
    private var joinConversationTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    // MARK: - Init

    init(session: any SessionManagerProtocol, showScannerOnAppear: Bool = false) {
        self.session = session
        self.showScannerOnAppear = showScannerOnAppear
    }

    // MARK: - Actions

    func newConversation() {
        guard addAccountResult == nil else { return }
        newConversationTask?.cancel()
        newConversationTask = Task {
            do {
                let addAccountResult = try session.addAccount()
                self.addAccountResult = addAccountResult
                let draftConversationComposer = addAccountResult.messagingService.draftConversationComposer()
                self.draftConversationComposer = draftConversationComposer
                draftConversationComposer.draftConversationWriter.createConversationWhenInboxReady()
                self.conversationViewModel = try conversationViewModel(
                    for: addAccountResult,
                    from: draftConversationComposer
                )
            } catch {
                Logger.error("Error starting new conversation: \(error.localizedDescription)")
            }
        }
    }

    func join(inviteCode: String) {
        guard let result = Invite.parse(temporaryInviteString: inviteCode) else {
            return
        }
        Logger.info("Scanned code: \(result)")
        joinConversation(
            inviteId: result.inviteId,
            inboxId: result.inboxId,
            inviteCode: result.code
        )
    }

    func deleteConversation() {
        newConversationTask?.cancel()
        draftConversationComposer = nil
        conversationViewModel = nil
        Task {
            guard let addAccountResult else { return }
            try session.deleteAccount(with: addAccountResult.providerId)
            self.addAccountResult = nil
        }
    }

    // MARK: - Private

    private func joinConversation(inviteId: String, inboxId: String, inviteCode: String) {
        joinConversationTask?.cancel()
        joinConversationTask = Task {
            do {
                if self.addAccountResult == nil {
                    Logger.info("No account found, creating one while joining conversation...")
                    let addAccountResult = try session.addAccount()
                    self.addAccountResult = addAccountResult
                }

                guard let addAccountResult else {
                    Logger.error("Failed adding account while joining conversation")
                    return
                }

                if self.draftConversationComposer == nil {
                    Logger.info("Setting up draft composer for joining conversation...")
                    let draftConversationComposer = addAccountResult.messagingService.draftConversationComposer()
                    draftConversationComposer.draftConversationWriter.createConversationWhenInboxReady()
                    self.draftConversationComposer = draftConversationComposer
                }

                guard let draftConversationComposer else {
                    Logger.error("Failed getting conversation composer while joining conversation")
                    return
                }

                if self.conversationViewModel == nil {
                    Logger.info("ConversationViewModel is `nil`... creating a new one.")
                    self.conversationViewModel = try conversationViewModel(
                        for: addAccountResult,
                        from: draftConversationComposer
                    )
                }

                draftConversationComposer
                    .draftConversationWriter
                    .joinConversationWhenInboxReady(
                        inviteId: inviteId,
                        inviterInboxId: inboxId,
                        inviteCode: inviteCode
                    )
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
        }
        .store(in: &cancellables)
    }

    func conversationViewModel(
        for addAccountResult: AddAccountResultType,
        from draftConversationComposer: any DraftConversationComposerProtocol
    ) throws -> ConversationViewModel {
        let draftConversation = try draftConversationComposer.draftConversationRepository.fetchConversation() ?? .empty(
            id: draftConversationComposer.draftConversationRepository.conversationId
        )
        let viewModel: ConversationViewModel = .init(
            conversation: draftConversation,
            myProfileWriter: draftConversationComposer.myProfileWriter,
            myProfileRepository: addAccountResult.messagingService.myProfileRepository(),
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
