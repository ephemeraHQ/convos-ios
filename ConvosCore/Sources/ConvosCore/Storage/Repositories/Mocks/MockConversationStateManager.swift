import Combine
import Foundation
import GRDB

public class MockConversationStateManager: ConversationStateManagerProtocol {
    // MARK: - State Properties

    public private(set) var currentState: ConversationStateMachine.State = .uninitialized
    private var observers: [WeakObserver] = []

    private struct WeakObserver {
        weak var observer: ConversationStateObserver?
    }

    // MARK: - DraftConversationWriterProtocol Properties

    private let conversationIdSubject: CurrentValueSubject<String, Never>

    public var conversationId: String {
        conversationIdSubject.value
    }

    public var conversationIdPublisher: AnyPublisher<String, Never> {
        conversationIdSubject.eraseToAnyPublisher()
    }

    public var sentMessage: AnyPublisher<String, Never> {
        Just("").eraseToAnyPublisher()
    }

    // MARK: - Dependencies

    public let myProfileWriter: any MyProfileWriterProtocol = MockMyProfileWriter()
    public let draftConversationRepository: any DraftConversationRepositoryProtocol = MockDraftConversationRepository()
    public let conversationConsentWriter: any ConversationConsentWriterProtocol = MockConversationConsentWriter()
    public let conversationLocalStateWriter: any ConversationLocalStateWriterProtocol = MockConversationLocalStateWriter()
    public let conversationMetadataWriter: any ConversationMetadataWriterProtocol = MockConversationMetadataWriter()

    // MARK: - Initialization

    public init() {
        self.conversationIdSubject = .init("mock-conversation-\(UUID().uuidString)")
    }

    // MARK: - State Management

    public func waitForConversationReadyResult(timeout: TimeInterval = 10.0) async throws -> ConversationReadyResult {
        // Mock implementation returns immediate success
        return ConversationReadyResult(conversationId: conversationId, origin: .created)
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

    public func observeState(_ handler: @escaping (ConversationStateMachine.State) -> Void) -> ConversationStateObserverHandle {
        let observer = ClosureConversationStateObserver(handler: handler)
        addObserver(observer)
        return ConversationStateObserverHandle(observer: observer, manager: self)
    }

    // MARK: - DraftConversationWriterProtocol Methods

    public func createConversation() async throws {
        currentState = .creating
        notifyObservers(currentState)

        // Simulate async operation
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 second

        let result = ConversationReadyResult(conversationId: conversationId, origin: .created)
        currentState = .ready(result)
        notifyObservers(currentState)
    }

    public func joinConversation(inviteCode: String) async throws {
        currentState = .validating(inviteCode: inviteCode)
        notifyObservers(currentState)

        // Simulate async operation
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 second

        let result = ConversationReadyResult(conversationId: conversationId, origin: .joined)
        currentState = .ready(result)
        notifyObservers(currentState)
    }

    public func send(text: String) async throws {
        // Mock implementation - no-op
    }

    public func delete() async {
        currentState = .deleting
        notifyObservers(currentState)

        // Simulate async operation
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second

        currentState = .uninitialized
        notifyObservers(currentState)
    }

    // MARK: - Private Helpers

    private func notifyObservers(_ state: ConversationStateMachine.State) {
        observers = observers.compactMap { weakObserver in
            guard let observer = weakObserver.observer else { return nil }
            observer.conversationStateDidChange(state)
            return weakObserver
        }
    }
}
