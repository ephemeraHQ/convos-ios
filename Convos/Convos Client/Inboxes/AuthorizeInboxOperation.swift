import Combine
import Foundation
import GRDB

protocol AuthorizeInboxOperationProtocol {
    var state: InboxStateMachine.State { get }
    var statePublisher: AnyPublisher<InboxStateMachine.State, Never> { get }
    var messagingPublisher: AnyPublisher<any MessagingServiceProtocol, Never> { get }

    func authorize()
    func register(displayName: String)
    func stop()
}

class AuthorizeInboxOperation: AuthorizeInboxOperationProtocol {
    var state: InboxStateMachine.State {
        stateMachine.state
    }

    var statePublisher: AnyPublisher<InboxStateMachine.State, Never> {
        stateMachine.statePublisher
    }

    let messagingPublisher: AnyPublisher<any MessagingServiceProtocol, Never>

    private let stateMachine: InboxStateMachine
    private var cancellables: Set<AnyCancellable> = []
    private var task: Task<Void, Never>?

    init(
        inbox: any AuthServiceInboxType,
        databaseReader: any DatabaseReader,
        databaseWriter: any DatabaseWriter,
        environment: AppEnvironment
    ) {
        let inboxWriter = InboxWriter(databaseWriter: databaseWriter)
        stateMachine = InboxStateMachine(
            inbox: inbox,
            inboxWriter: inboxWriter,
            environment: environment
        )
        messagingPublisher = stateMachine.statePublisher.compactMap { state in
            switch state {
            case let .ready(client, apiClient):
                let messagingService = MessagingService(
                    client: client,
                    apiClient: apiClient,
                    databaseWriter: databaseWriter,
                    databaseReader: databaseReader
                )
                return messagingService
            default:
                return nil
            }
        }.eraseToAnyPublisher()
    }

    deinit {
        task?.cancel()
        task = nil
    }

    func authorize() {
        task?.cancel()
        task = Task {
            await stateMachine.authorize()
        }
    }

    func register(displayName: String) {
        task?.cancel()
        task = Task {
            await stateMachine.register(displayName: displayName)
        }
    }

    func stop() {
        task?.cancel()
        task = Task {
            await stateMachine.stop()
        }
    }
}
