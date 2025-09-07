import Combine
import Foundation
import GRDB

public protocol DraftConversationWriterProtocol: OutgoingMessageWriterProtocol {
    var draftConversationId: String { get }
    var conversationId: String { get }
    var conversationIdPublisher: AnyPublisher<String, Never> { get }
    var conversationMetadataWriter: any ConversationMetadataWriterProtocol { get }

    func createConversation() async throws
    func requestToJoin(inviteCode: String) async throws
    func delete() async
}

class DraftConversationWriter: DraftConversationWriterProtocol {
    private let databaseReader: any DatabaseReader
    private let databaseWriter: any DatabaseWriter
    private let inboxStateManager: InboxStateManager
    private let sentMessageSubject: PassthroughSubject<String, Never> = .init()
    let conversationMetadataWriter: any ConversationMetadataWriterProtocol

    private let stateMachine: ConversationStateMachine
    private var stateObservationTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = .init()

    var sentMessage: AnyPublisher<String, Never> {
        sentMessageSubject.eraseToAnyPublisher()
    }

    let draftConversationId: String
    private let conversationIdSubject: CurrentValueSubject<String, Never>
    var conversationId: String {
        conversationIdSubject.value
    }
    var conversationIdPublisher: AnyPublisher<String, Never> {
        conversationIdSubject.eraseToAnyPublisher()
    }

    init(inboxStateManager: InboxStateManager,
         databaseReader: any DatabaseReader,
         databaseWriter: any DatabaseWriter,
         draftConversationId: String) {
        self.inboxStateManager = inboxStateManager
        self.databaseReader = databaseReader
        self.databaseWriter = databaseWriter
        self.draftConversationId = draftConversationId
        self.conversationIdSubject = .init(draftConversationId)
        self.conversationMetadataWriter = ConversationMetadataWriter(
            inboxStateManager: inboxStateManager,
            databaseWriter: databaseWriter
        )

        let inviteWriter = InviteWriter(databaseWriter: databaseWriter)
        self.stateMachine = ConversationStateMachine(
            draftConversationId: draftConversationId,
            inboxStateManager: inboxStateManager,
            databaseReader: databaseReader,
            databaseWriter: databaseWriter,
            inviteWriter: inviteWriter
        )

        setupStateObservation()
    }

    deinit {
        stateObservationTask?.cancel()
        cancellables.removeAll()
    }

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

    private func waitForConversationReadyResult() async throws -> ConversationReadyResult {
        let timeoutDuration: TimeInterval = 5.0 // 5 seconds timeout

        return try await withTimeout(
            seconds: timeoutDuration,
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

    @MainActor
    private func handleStateChange(_ state: ConversationStateMachine.State) {
        switch state {
        case .ready(let result):
            conversationIdSubject.send(result.externalConversationId)
        case .creating, .joining:
            // Keep using draft ID during creation/joining
            conversationIdSubject.send(draftConversationId)
        default:
            break
        }
    }

    func createConversation() async throws {
        await stateMachine.create()
        _ = try await waitForConversationReadyResult()
    }

    func requestToJoin(inviteCode: String) async throws {
        await stateMachine.join(inviteCode: inviteCode)
        _ = try await waitForConversationReadyResult()
    }

    func send(text: String) async throws {
        await stateMachine.sendMessage(text: text)
        sentMessageSubject.send(text)
    }

    func delete() async {
        await stateMachine.delete()
    }
}
