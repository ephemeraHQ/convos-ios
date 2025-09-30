import Combine
import Foundation
import GRDB
import Observation

// MARK: - Observer Protocol

public protocol ConversationStateObserver: AnyObject {
    func conversationStateDidChange(_ state: ConversationStateMachine.State)
}

// MARK: - StateManager Protocol

public protocol ConversationStateManagerProtocol: AnyObject, DraftConversationWriterProtocol {
    // State Management
    var currentState: ConversationStateMachine.State { get }
    func waitForConversationReadyResult(timeout: TimeInterval) async throws -> ConversationReadyResult

    // Observer Management
    func addObserver(_ observer: ConversationStateObserver)
    func removeObserver(_ observer: ConversationStateObserver)
    func observeState(_ handler: @escaping (ConversationStateMachine.State) -> Void) -> ConversationStateObserverHandle

    // Dependencies
    var myProfileWriter: any MyProfileWriterProtocol { get }
    var draftConversationRepository: any DraftConversationRepositoryProtocol { get }
    var conversationConsentWriter: any ConversationConsentWriterProtocol { get }
    var conversationLocalStateWriter: any ConversationLocalStateWriterProtocol { get }
    var conversationMetadataWriter: any ConversationMetadataWriterProtocol { get }
}

// MARK: - State Manager Implementation

@Observable
public final class ConversationStateManager: ConversationStateManagerProtocol {
    // MARK: - State Properties

    public private(set) var currentState: ConversationStateMachine.State = .uninitialized
    public private(set) var isReady: Bool = false
    public private(set) var hasError: Bool = false
    public private(set) var errorMessage: String?

    // MARK: - DraftConversationWriterProtocol Properties

    private let conversationIdSubject: CurrentValueSubject<String, Never>
    private let sentMessageSubject: PassthroughSubject<String, Never> = .init()

    public var conversationId: String {
        conversationIdSubject.value
    }

    public var conversationIdPublisher: AnyPublisher<String, Never> {
        conversationIdSubject.eraseToAnyPublisher()
    }

    public var sentMessage: AnyPublisher<String, Never> {
        sentMessageSubject.eraseToAnyPublisher()
    }

    // MARK: - Dependencies

    public let myProfileWriter: any MyProfileWriterProtocol
    public let conversationConsentWriter: any ConversationConsentWriterProtocol
    public let conversationLocalStateWriter: any ConversationLocalStateWriterProtocol
    public let conversationMetadataWriter: any ConversationMetadataWriterProtocol
    public let draftConversationRepository: any DraftConversationRepositoryProtocol

    // MARK: - Private Properties

    private let inboxStateManager: any InboxStateManagerProtocol
    private let identityStore: any KeychainIdentityStoreProtocol
    private let databaseReader: any DatabaseReader
    private let databaseWriter: any DatabaseWriter
    private let stateMachine: ConversationStateMachine

    private var stateObservationTask: Task<Void, Never>?
    private var observers: [WeakObserver] = []
    private var cancellables: Set<AnyCancellable> = .init()

    private struct WeakObserver {
        weak var observer: ConversationStateObserver?
    }

    // MARK: - Initialization

    public init(
        inboxStateManager: any InboxStateManagerProtocol,
        identityStore: any KeychainIdentityStoreProtocol,
        databaseReader: any DatabaseReader,
        databaseWriter: any DatabaseWriter
    ) {
        self.inboxStateManager = inboxStateManager
        self.identityStore = identityStore
        self.databaseReader = databaseReader
        self.databaseWriter = databaseWriter
        self.conversationIdSubject = .init(DBConversation.generateDraftConversationId())

        // Initialize writers
        let inviteWriter = InviteWriter(identityStore: identityStore, databaseWriter: databaseWriter)
        self.conversationMetadataWriter = ConversationMetadataWriter(
            inboxStateManager: inboxStateManager,
            inviteWriter: inviteWriter,
            databaseWriter: databaseWriter
        )

        self.myProfileWriter = MyProfileWriter(
            inboxStateManager: inboxStateManager,
            databaseWriter: databaseWriter
        )

        self.conversationConsentWriter = ConversationConsentWriter(
            inboxStateManager: inboxStateManager,
            databaseWriter: databaseWriter
        )

        self.conversationLocalStateWriter = ConversationLocalStateWriter(
            databaseWriter: databaseWriter
        )

        self.draftConversationRepository = DraftConversationRepository(
            dbReader: databaseReader,
            conversationId: conversationIdSubject.value,
            conversationIdPublisher: conversationIdSubject.eraseToAnyPublisher(),
            inboxStateManager: inboxStateManager
        )

        // Initialize state machine
        self.stateMachine = ConversationStateMachine(
            inboxStateManager: inboxStateManager,
            identityStore: identityStore,
            databaseReader: databaseReader,
            databaseWriter: databaseWriter
        )

        setupStateObservation()
    }

    deinit {
        stateObservationTask?.cancel()
        cancellables.removeAll()
        observers.removeAll()
    }

    // MARK: - State Observation Setup

    private func setupStateObservation() {
        stateObservationTask = Task { [weak self] in
            guard let self else { return }

            for await state in await stateMachine.stateSequence {
                await self.handleStateChange(state)

                if Task.isCancelled {
                    break
                }
            }
        }
    }

    @MainActor
    private func handleStateChange(_ state: ConversationStateMachine.State) {
        currentState = state

        switch state {
        case .ready(let result):
            isReady = true
            hasError = false
            errorMessage = nil
            conversationIdSubject.send(result.conversationId)

        case .error(let error):
            isReady = false
            hasError = true
            errorMessage = error.localizedDescription

        default:
            isReady = false
            hasError = false
            errorMessage = nil
        }

        notifyObservers(state)
    }

    // MARK: - Observer Management

    public func addObserver(_ observer: ConversationStateObserver) {
        observers.removeAll { $0.observer == nil }
        observers.append(WeakObserver(observer: observer))
        observer.conversationStateDidChange(currentState)
    }

    public func removeObserver(_ observer: ConversationStateObserver) {
        observers.removeAll { $0.observer === observer }
    }

    private func notifyObservers(_ state: ConversationStateMachine.State) {
        observers = observers.compactMap { weakObserver in
            guard let observer = weakObserver.observer else { return nil }
            observer.conversationStateDidChange(state)
            return weakObserver
        }
    }

    public func observeState(_ handler: @escaping (ConversationStateMachine.State) -> Void) -> ConversationStateObserverHandle {
        let observer = ClosureConversationStateObserver(handler: handler)
        addObserver(observer)
        return ConversationStateObserverHandle(observer: observer, manager: self)
    }

    // MARK: - State Management

    public func waitForConversationReadyResult(timeout: TimeInterval = 10.0) async throws -> ConversationReadyResult {
        return try await withTimeout(
            seconds: timeout,
            timeoutError: ConversationStateMachineError.timedOut
        ) {
            for await state in await self.stateMachine.stateSequence {
                switch state {
                case .ready(let result):
                    return result
                case .error(let error):
                    throw error
                default:
                    continue
                }
            }
            throw ConversationStateMachineError.timedOut
        }
    }

    // MARK: - DraftConversationWriterProtocol Methods

    public func createConversation() async throws {
        await stateMachine.create()
        _ = try await waitForConversationReadyResult()
    }

    public func joinConversation(inviteCode: String) async throws {
        await stateMachine.join(inviteCode: inviteCode)
        _ = try await waitForConversationReadyResult()
    }

    public func send(text: String) async throws {
        await stateMachine.sendMessage(text: text)
        sentMessageSubject.send(text)
    }

    public func delete() async {
        await stateMachine.delete()
    }
}

// MARK: - Observer Helpers

public final class ClosureConversationStateObserver: ConversationStateObserver {
    private let handler: (ConversationStateMachine.State) -> Void

    init(handler: @escaping (ConversationStateMachine.State) -> Void) {
        self.handler = handler
    }

    public func conversationStateDidChange(_ state: ConversationStateMachine.State) {
        handler(state)
    }
}

public final class ConversationStateObserverHandle {
    private var observer: ClosureConversationStateObserver?
    private weak var manager: (any ConversationStateManagerProtocol)?

    init(observer: ClosureConversationStateObserver, manager: any ConversationStateManagerProtocol) {
        self.observer = observer
        self.manager = manager
    }

    public func cancel() {
        if let observer = observer {
            manager?.removeObserver(observer)
        }
        observer = nil
        manager = nil
    }

    deinit {
        cancel()
    }
}

// MARK: - Component Helper

@MainActor
open class ConversationStateAwareComponent {
    private var observerHandle: ConversationStateObserverHandle?
    private let stateManager: ConversationStateManager
    public var state: ConversationStateMachine.State?

    public init(stateManager: ConversationStateManager) {
        self.stateManager = stateManager
        observerHandle = stateManager.observeState { [weak self] state in
            Task { @MainActor in
                self?.state = state
                self?.conversationStateDidChange(state)
            }
        }
    }

    deinit {
        observerHandle?.cancel()
    }

    open func conversationStateDidChange(_ state: ConversationStateMachine.State) {}

    public var isConversationReady: Bool {
        stateManager.isReady
    }

    public var currentConversationState: ConversationStateMachine.State {
        stateManager.currentState
    }

    public func waitForConversationReadyResult() async throws -> ConversationReadyResult {
        try await stateManager.waitForConversationReadyResult(timeout: 10.0)
    }
}
