import Combine
import Foundation
import GRDB

public protocol MyProfileRepositoryProtocol {
    var myProfilePublisher: AnyPublisher<Profile, Never> { get }
    func fetch(inboxId: String) throws -> Profile
}

class MyProfileRepository: MyProfileRepositoryProtocol {
    let myProfilePublisher: AnyPublisher<Profile, Never>

    private let databaseReader: any DatabaseReader
    private var stateObserver: StateObserverHandle?
    private let profileSubject: PassthroughSubject<Profile?, Never> = .init()
    private var cancellables: Set<AnyCancellable> = .init()

    init(
        inboxStateManager: InboxStateManager,
        databaseReader: any DatabaseReader
    ) {
        self.databaseReader = databaseReader

        // Set up publisher that emits profiles when inbox state changes
        self.myProfilePublisher = profileSubject
            .compactMap { $0 }
            .eraseToAnyPublisher()

        stateObserver = inboxStateManager.observeState { [weak self] state in
            self?.handleInboxStateChange(state)
        }
    }

    deinit {
        stateObserver?.cancel()
    }

    private func handleInboxStateChange(_ state: InboxStateMachine.State) {
        switch state {
        case .ready(let result):
            let inboxId = result.client.inboxId
            startObservingProfile(for: inboxId)
        case .uninitialized, .stopping:
            profileSubject.send(nil)
        default:
            break
        }
    }

    private func startObservingProfile(for inboxId: String) {
        let observation = ValueObservation
            .tracking { db in
                try MemberProfile
                    .fetchOne(db, key: inboxId)?
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

    func fetch(inboxId: String) throws -> Profile {
        try databaseReader.read { db in
            try MemberProfile
                .fetchOne(db, key: inboxId)?
                .hydrateProfile() ?? .empty(inboxId: inboxId)
        }
    }
}
