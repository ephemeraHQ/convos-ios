import Combine
import OrderedCollections
import SwiftUI

@Observable
class NewConversationState: Identifiable {
    private var cancellables: Set<AnyCancellable> = []
    private let session: any SessionManagerProtocol
    private(set) var conversationState: ConversationState?
    private(set) var draftConversationComposer: (any DraftConversationComposerProtocol)? {
        didSet {
            setupObservations()
        }
    }

    private(set) var showJoinConversation: Bool = true // false once someone joins or a message is sent
    private(set) var promptToKeepConversation: Bool = true
    private(set) var showScannerOnAppear: Bool

    private var addAccountResult: AddAccountResultType?
    private var newConversationTask: Task<Void, Never>?
    private var joinConversationTask: Task<Void, Never>?

    init(session: any SessionManagerProtocol, showScannerOnAppear: Bool = false) {
        self.session = session
        self.showScannerOnAppear = showScannerOnAppear
    }

    func newConversation() {
        newConversationTask?.cancel()
        newConversationTask = Task {
            do {
                let addAccountResult = try session.addAccount()
                self.addAccountResult = addAccountResult
                let draftConversationComposer = addAccountResult.messagingService.draftConversationComposer()
                draftConversationComposer.draftConversationWriter.createConversationWhenInboxReady()
                await MainActor.run {
                    self.draftConversationComposer = draftConversationComposer
                    self.conversationState = ConversationState(
                        myProfileRepository: addAccountResult.messagingService.myProfileRepository(),
                        conversationRepository: draftConversationComposer.draftConversationRepository
                    )
                }
            } catch {
                Logger.error("Error starting new conversation: \(error.localizedDescription)")
            }
        }
    }

    func joinConversation(inboxId: String, inviteCode: String) {
        joinConversationTask?.cancel()
        joinConversationTask = Task {
            do {
                if self.addAccountResult == nil {
                    let addAccountResult = try session.addAccount()
                    self.addAccountResult = addAccountResult
                }

                guard let addAccountResult else {
                    Logger.error("Failed adding account while joining conversation")
                    return
                }

                if self.draftConversationComposer == nil {
                    let draftConversationComposer = addAccountResult.messagingService.draftConversationComposer()
                    draftConversationComposer.draftConversationWriter.createConversationWhenInboxReady()
                    self.draftConversationComposer = draftConversationComposer
                }

                guard let draftConversationComposer else {
                    Logger.error("Failed getting conversation composer while joining conversation")
                    return
                }

                draftConversationComposer.draftConversationWriter
                    .joinConversationWhenInboxReady(inboxId: inboxId, inviteCode: inviteCode)
                await MainActor.run {
                    self.draftConversationComposer = draftConversationComposer
                    self.conversationState = ConversationState(
                        myProfileRepository: addAccountResult.messagingService.myProfileRepository(),
                        conversationRepository: draftConversationComposer.draftConversationRepository
                    )
                }
            } catch {
                Logger.error("Error joining new conversation: \(error.localizedDescription)")
            }
        }
    }

    func deleteConversation() {
        newConversationTask?.cancel()
        draftConversationComposer = nil
        conversationState = nil
        Task {
            guard let addAccountResult else { return }
            try session.deleteAccount(with: addAccountResult.providerId)
            self.addAccountResult = nil
        }
    }

    private func setupObservations() {
        cancellables.removeAll()

        guard let draftConversationComposer else {
            return
        }

        Publishers.Merge(
            draftConversationComposer.draftConversationWriter.sentMessage.map { _ in () },
            draftConversationComposer.draftConversationRepository.membersPublisher
                .filter { !$0.isEmpty }
                .dropFirst()
                .map { _ in () }
        )
        .eraseToAnyPublisher()
        .receive(on: DispatchQueue.main)
        .sink { [weak self] in
            guard let self else { return }
            showJoinConversation = false
            promptToKeepConversation = false
        }
        .store(in: &cancellables)
    }
}
