import Combine
import Foundation
import GRDB

public protocol MyProfileRepositoryProtocol {
    var myProfilePublisher: AnyPublisher<Profile, Never> { get }
    func fetch() throws -> Profile
}

class MyProfileRepository: MyProfileRepositoryProtocol {
    let myProfilePublisher: AnyPublisher<Profile, Never>

    private let databaseReader: any DatabaseReader
    private let inboxStateManager: any InboxStateManagerProtocol
    private var conversationId: String {
        conversationIdSubject.value
    }
    private let conversationIdSubject: CurrentValueSubject<String, Never>
    private var stateObserver: StateObserverHandle?
    private let profileSubject: CurrentValueSubject<Profile?, Never> = .init(nil)
    private var conversationIdCancellable: AnyCancellable?
    private var cancellables: Set<AnyCancellable> = .init()

    init(
        inboxStateManager: any InboxStateManagerProtocol,
        databaseReader: any DatabaseReader,
        conversationId: String
    ) {
        self.databaseReader = databaseReader
        self.inboxStateManager = inboxStateManager
        self.conversationIdSubject = .init(conversationId)

        // Set up publisher that emits profiles when inbox state or conversation changes
        self.myProfilePublisher = profileSubject
            .compactMap { $0 }
            .eraseToAnyPublisher()

        stateObserver = inboxStateManager.observeState { [weak self] state in
            self?.handleInboxStateChange(state)
        }
    }

    init(
        inboxStateManager: any InboxStateManagerProtocol,
        databaseReader: any DatabaseReader,
        conversationId: String,
        conversationIdPublisher: AnyPublisher<String, Never>
    ) {
        self.databaseReader = databaseReader
        self.inboxStateManager = inboxStateManager
        self.conversationIdSubject = .init(conversationId)

        // Set up publisher that emits profiles when inbox state or conversation changes
        self.myProfilePublisher = profileSubject
            .compactMap { $0 }
            .eraseToAnyPublisher()

        stateObserver = inboxStateManager.observeState { [weak self] state in
            self?.handleInboxStateChange(state)
        }

        conversationIdCancellable = conversationIdPublisher.sink { [weak self] conversationId in
            guard let self else { return }
            Logger.info("Updating conversation id to \(conversationId)")
            self.conversationIdSubject.send(conversationId)
            // Re-observe profile for the new conversation
            if case .ready(_, let result) = self.inboxStateManager.currentState {
                self.startObservingProfile(for: result.client.inboxId, conversationId: conversationId)
            }
        }
    }

    deinit {
        stateObserver?.cancel()
        conversationIdCancellable?.cancel()
    }

    private func handleInboxStateChange(_ state: InboxStateMachine.State) {
        switch state {
        case .ready(_, let result):
            let inboxId = result.client.inboxId
            startObservingProfile(for: inboxId, conversationId: conversationId)
        case .idle, .stopping:
            profileSubject.send(nil)
        default:
            break
        }
    }

    private func startObservingProfile(for inboxId: String, conversationId: String) {
        // Cancel previous observations
        cancellables.removeAll()

        let observation = ValueObservation
            .tracking { db in
                try MemberProfile
                    .fetchOne(db, conversationId: conversationId, inboxId: inboxId)?
                    .hydrateProfile() ?? .empty(inboxId: inboxId)
            }
            .publisher(in: databaseReader)
            .replaceError(with: .empty(inboxId: inboxId))

        observation
            .sink { [weak self] profile in
                self?.profileSubject.send(profile)
            }
            .store(in: &cancellables)
    }

    func fetch() throws -> Profile {
        guard case .ready(_, let result) = inboxStateManager.currentState else {
            throw MyProfileRepositoryError.inboxNotReady
        }
        let inboxId = result.client.inboxId

        return try databaseReader.read { db in
            try MemberProfile
                .fetchOne(db, conversationId: conversationId, inboxId: inboxId)?
                .hydrateProfile() ?? .empty(inboxId: inboxId)
        }
    }
}

enum MyProfileRepositoryError: Error {
    case inboxNotReady
}
