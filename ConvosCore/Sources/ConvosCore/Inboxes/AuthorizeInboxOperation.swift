import Combine
import Foundation
import GRDB

protocol AuthorizeInboxOperationProtocol {
    var inbox: any AuthServiceInboxType { get }
    var state: InboxStateMachine.State { get }
    var statePublisher: AnyPublisher<InboxStateMachine.State, Never> { get }
    var inboxReadyPublisher: InboxReadyResultPublisher { get }

    func authorize()
    func register(displayName: String?)
    func deleteAndStop()
    func stop()
}

class AuthorizeInboxOperation: AuthorizeInboxOperationProtocol {
    let inbox: any AuthServiceInboxType

    var state: InboxStateMachine.State {
        stateMachine.state
    }

    var statePublisher: AnyPublisher<InboxStateMachine.State, Never> {
        stateMachine.statePublisher
    }

    let inboxReadyPublisher: InboxReadyResultPublisher

    private let stateMachine: InboxStateMachine
    private var cancellables: Set<AnyCancellable> = []
    private var task: Task<Void, Never>?

    init(
        inbox: any AuthServiceInboxType,
        authService: any LocalAuthServiceProtocol,
        databaseReader: any DatabaseReader,
        databaseWriter: any DatabaseWriter,
        environment: AppEnvironment,
        isNotificationServiceExtension: Bool = false
    ) {
        self.inbox = inbox
        let inboxWriter = InboxWriter(databaseWriter: databaseWriter)
        stateMachine = InboxStateMachine(
            inbox: inbox,
            inboxWriter: inboxWriter,
            authService: authService,
            syncingManager: SyncingManager(databaseWriter: databaseWriter),
            inviteJoinRequestsManager: InviteJoinRequestsManager(
                databaseReader: databaseReader,
                databaseWriter: databaseWriter
            ),
            environment: environment,
            isNotificationServiceExtension: isNotificationServiceExtension
        )
        inboxReadyPublisher = stateMachine
            .statePublisher
            .compactMap { state in
                switch state {
                case let .ready(result):
                    return result
                default:
                    return nil
                }
            }
            .eraseToAnyPublisher()
    }

    deinit {
        task?.cancel()
        task = nil
    }

    func authorize() {
        task?.cancel()
        task = Task { [stateMachine] in
            await stateMachine.authorize()
        }
    }

    func register(displayName: String?) {
        task?.cancel()
        task = Task { [stateMachine] in
            await stateMachine.register(displayName: displayName)
        }
    }

    func deleteAndStop() {
        task?.cancel()
        task = Task { [stateMachine] in
            await stateMachine.deleteAndStop()
        }
    }

    func stop() {
        task?.cancel()
        task = Task { [stateMachine] in
            await stateMachine.stop()
        }
    }
}
