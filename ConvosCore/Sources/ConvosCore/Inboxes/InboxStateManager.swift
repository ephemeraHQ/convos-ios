import Foundation
import Observation

public protocol InboxStateObserver: AnyObject {
    func inboxStateDidChange(_ state: InboxStateMachine.State)
}

@Observable
public final class InboxStateManager {
    public private(set) var currentState: InboxStateMachine.State = .uninitialized
    public private(set) var isReady: Bool = false
    public private(set) var hasError: Bool = false
    public private(set) var errorMessage: String?

    private(set) weak var stateMachine: InboxStateMachine?
    private var stateTask: Task<Void, Never>?
    private var observers: [WeakObserver] = []

    private struct WeakObserver {
        weak var observer: InboxStateObserver?
    }

    public init(stateMachine: InboxStateMachine) {
        observe(stateMachine)
    }

    deinit {
        observers.removeAll()
        stateTask?.cancel()
    }

    private func observe(_ stateMachine: InboxStateMachine) {
        self.stateMachine = stateMachine
        stateTask?.cancel()

        stateTask = Task { [weak self] in
            guard let self else { return }
            for await state in await stateMachine.stateSequence {
                await self.handleStateChange(state)
            }
        }
    }

    private func handleStateChange(_ state: InboxStateMachine.State) async {
        currentState = state
        isReady = state.isReady

        switch state {
        case .error(let error):
            hasError = true
            errorMessage = error.localizedDescription
        default:
            hasError = false
            errorMessage = nil
        }

        notifyObservers(state)
    }

    public func addObserver(_ observer: InboxStateObserver) {
        observers.removeAll { $0.observer == nil }
        observers.append(WeakObserver(observer: observer))
        observer.inboxStateDidChange(currentState)
    }

    public func removeObserver(_ observer: InboxStateObserver) {
        observers.removeAll { $0.observer === observer }
    }

    private func notifyObservers(_ state: InboxStateMachine.State) {
        observers = observers.compactMap { weakObserver in
            guard let observer = weakObserver.observer else { return nil }
            observer.inboxStateDidChange(state)
            return weakObserver
        }
    }

    public func waitForInboxReadyResult() async throws -> InboxReadyResult {
        guard let stateMachine = stateMachine else {
            throw InboxStateError.inboxNotReady
        }

        for await state in await stateMachine.stateSequence {
            switch state {
            case .ready(let result):
                return result
            case .error(let error):
                throw error
            default:
                continue
            }
        }

        throw InboxStateError.inboxNotReady
    }

    public func observeState(_ handler: @escaping (InboxStateMachine.State) -> Void) -> StateObserverHandle {
        let observer = ClosureStateObserver(handler: handler)
        addObserver(observer)
        return StateObserverHandle(observer: observer, manager: self)
    }
}

public final class ClosureStateObserver: InboxStateObserver {
    private let handler: (InboxStateMachine.State) -> Void

    init(handler: @escaping (InboxStateMachine.State) -> Void) {
        self.handler = handler
    }

    public func inboxStateDidChange(_ state: InboxStateMachine.State) {
        handler(state)
    }
}

public final class StateObserverHandle {
    private var observer: ClosureStateObserver?
    private weak var manager: InboxStateManager?

    init(observer: ClosureStateObserver, manager: InboxStateManager) {
        self.observer = observer
        self.manager = manager
    }

    public func cancel() {
        if let observer = observer {
            manager?.removeObserver(observer)
        }
    }

    deinit {
        cancel()
    }
}

@MainActor
open class InboxAwareComponent {
    private var observerHandle: StateObserverHandle?
    private let stateManager: InboxStateManager
    var state: InboxStateMachine.State?

    public init(stateManager: InboxStateManager) {
        self.stateManager = stateManager
        observerHandle = stateManager.observeState { state in
            self.state = state
        }
    }

    deinit {
        observerHandle?.cancel()
    }

    open func inboxStateDidChange(_ state: InboxStateMachine.State) {}

    public var isInboxReady: Bool {
        stateManager.isReady
    }

    public var currentInboxState: InboxStateMachine.State {
        stateManager.currentState
    }

    public func waitForInboxReadyResult() async throws -> InboxReadyResult {
        try await stateManager.waitForInboxReadyResult()
    }
}
