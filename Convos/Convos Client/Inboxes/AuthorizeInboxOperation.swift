import Combine
import Foundation
import GRDB

enum AuthorizeInboxOperationStatus {
    case idle,
         starting,
         authorizing,
         registering,
         ready(any MessagingServiceProtocol),
         error(Error),
         stopping
}

protocol AuthorizeInboxOperationProtocol {
    var statusPublisher: AnyPublisher<AuthorizeInboxOperationStatus, Never> { get }

    func authorize()
    func register(displayName: String)
    func stop()
}

class AuthorizeInboxOperation: AuthorizeInboxOperationProtocol {
    let statusPublisher: AnyPublisher<AuthorizeInboxOperationStatus, Never>

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
        statusPublisher = stateMachine.statePublisher.map { state in
            switch state {
            case .uninitialized:
                return .idle
            case .initializing:
                return .starting
            case .authorizing:
                return .authorizing
            case .registering:
                return .registering
            case let .ready(client, apiClient):
                let messagingService = MessagingService(
                    client: client,
                    apiClient: apiClient,
                    databaseWriter: databaseWriter,
                    databaseReader: databaseReader
                )
                return .ready(messagingService)
            case let .error(error):
                return .error(error)
            case .stopping:
                return .stopping
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
