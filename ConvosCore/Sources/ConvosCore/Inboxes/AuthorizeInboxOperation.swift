import Combine
import Foundation
import GRDB

public typealias InboxReadyResultPublisher = AnyPublisher<InboxReadyResult, Never>

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
        stateSubject.value
    }

    var statePublisher: AnyPublisher<InboxStateMachine.State, Never> {
        stateSubject.eraseToAnyPublisher()
    }

    let inboxReadyPublisher: InboxReadyResultPublisher

    private let stateMachine: InboxStateMachine
    private let stateSubject: CurrentValueSubject<InboxStateMachine.State, Never> = .init(.uninitialized)
    private var cancellables: Set<AnyCancellable> = []
    private var task: Task<Void, Never>?
    private var stateObservationTask: Task<Void, Never>?

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

        // Create push notification registrar only if not in notification service extension
        let pushNotificationRegistrar: PushNotificationRegistrarProtocol? = isNotificationServiceExtension ? nil : PushNotificationRegistrar(
            environment: environment,
            authService: authService,
            inbox: inbox
        )

        stateMachine = InboxStateMachine(
            inbox: inbox,
            inboxWriter: inboxWriter,
            authService: authService,
            syncingManager: SyncingManager(databaseWriter: databaseWriter),
            inviteJoinRequestsManager: InviteJoinRequestsManager(
                databaseReader: databaseReader,
                databaseWriter: databaseWriter
            ),
            pushNotificationRegistrar: pushNotificationRegistrar,
            refreshProfileWhenReady: !isNotificationServiceExtension,
            environment: environment,
        )

        inboxReadyPublisher = stateSubject
            .compactMap { state in
                switch state {
                case let .ready(result):
                    return result
                default:
                    return nil
                }
            }
            .eraseToAnyPublisher()

        Task { [weak self] in
            guard let self = self else { return }
            let currentState = await self.stateMachine.state
            await MainActor.run {
                self.stateSubject.send(currentState)
            }

            self.startStateObservation()
        }
    }

    deinit {
        task?.cancel()
        task = nil
        stateObservationTask?.cancel()
        stateObservationTask = nil
    }

    private func startStateObservation() {
        stateObservationTask = Task { [weak self] in
            guard let self = self else { return }
            let stateSequence = await self.stateMachine.stateSequence
            for await state in stateSequence {
                await MainActor.run {
                    self.stateSubject.send(state)
                }
            }
        }
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
