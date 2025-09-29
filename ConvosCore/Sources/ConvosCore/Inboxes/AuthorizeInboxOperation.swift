import Combine
import Foundation
import GRDB

extension AppEnvironment {
    var defaultIdentityStore: any KeychainIdentityStoreProtocol {
        switch self {
        case .local, .dev, .production:
            KeychainIdentityStore(accessGroup: keychainAccessGroup)
        case .tests:
            MockKeychainIdentityStore()
        }
    }
}

protocol AuthorizeInboxOperationProtocol {
    func stopAndDelete() async
    func stopAndDelete()
    func stop()
    func reset() async
    func registerForPushNotifications() async
}

final class AuthorizeInboxOperation: AuthorizeInboxOperationProtocol {
    let stateMachine: InboxStateMachine
    private var cancellables: Set<AnyCancellable> = []
    private var task: Task<Void, Never>?

    static func authorize(
        identityStore: any KeychainIdentityStoreProtocol,
        databaseReader: any DatabaseReader,
        databaseWriter: any DatabaseWriter,
        environment: AppEnvironment,
        startsStreamingServices: Bool,
        registersForPushNotifications: Bool = true
    ) -> AuthorizeInboxOperation {
        let operation = AuthorizeInboxOperation(
            identityStore: identityStore,
            databaseReader: databaseReader,
            databaseWriter: databaseWriter,
            environment: environment,
            startsStreamingServices: startsStreamingServices,
            registersForPushNotifications: registersForPushNotifications
        )
        operation.authorize()
        return operation
    }

    private init(
        identityStore: any KeychainIdentityStoreProtocol,
        databaseReader: any DatabaseReader,
        databaseWriter: any DatabaseWriter,
        environment: AppEnvironment,
        startsStreamingServices: Bool,
        registersForPushNotifications: Bool
    ) {
        let syncingManager = startsStreamingServices ? SyncingManager(
            identityStore: identityStore,
            databaseWriter: databaseWriter
        ) : nil
        let inviteJoinRequestsManager = startsStreamingServices ? InviteJoinRequestsManager(
            identityStore: identityStore,
            databaseReader: databaseReader,
        ) : nil
        let invitesRepository = InvitesRepository(databaseReader: databaseReader)
        stateMachine = InboxStateMachine(
            identityStore: identityStore,
            invitesRepository: invitesRepository,
            databaseWriter: databaseWriter,
            syncingManager: syncingManager,
            inviteJoinRequestsManager: inviteJoinRequestsManager,
            pushNotificationRegistrar: PushNotificationRegistrar(
                environment: environment
            ),
            autoRegistersForPushNotifications: registersForPushNotifications,
            environment: environment
        )
    }

    deinit {
        task?.cancel()
        task = nil
    }

    private func authorize() {
        task?.cancel()
        task = Task { [weak self] in
            guard let self else { return }
            await stateMachine.authorize()
        }
    }

    func reset() async {
        await stateMachine.reset()
    }

    func stopAndDelete() {
        task?.cancel()
        task = Task { [weak self] in
            guard let self else { return }
            await stateMachine.stopAndDelete()
        }
    }

    func stopAndDelete() async {
        task?.cancel()
        await stateMachine.stopAndDelete()
    }

    func stop() {
        task?.cancel()
        task = Task { [weak self] in
            guard let self else { return }
            await stateMachine.stop()
        }
    }

    func registerForPushNotifications() async {
        await stateMachine.registerForPushNotifications()
    }
}
