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
    func registerForPushNotifications() async
    func activateDeferredInbox(registersForPushNotifications: Bool) async
}

final class AuthorizeInboxOperation: AuthorizeInboxOperationProtocol {
    let stateMachine: InboxStateMachine
    private var cancellables: Set<AnyCancellable> = []
    private var task: Task<Void, Never>?

    static func authorize(
        inboxId: String,
        databaseReader: any DatabaseReader,
        databaseWriter: any DatabaseWriter,
        environment: AppEnvironment,
        startsStreamingServices: Bool,
        registersForPushNotifications: Bool = true,
        deferBackendInitialization: Bool = false,
        persistInboxOnReady: Bool = true
    ) -> AuthorizeInboxOperation {
        let operation = AuthorizeInboxOperation(
            databaseReader: databaseReader,
            databaseWriter: databaseWriter,
            environment: environment,
            shouldStartStreamingServicesOnReady: startsStreamingServices,
            registersForPushNotifications: registersForPushNotifications,
            deferBackendInitialization: deferBackendInitialization,
            persistInboxOnReady: persistInboxOnReady
        )
        operation.authorize(inboxId: inboxId)
        return operation
    }

    static func register(
        databaseReader: any DatabaseReader,
        databaseWriter: any DatabaseWriter,
        environment: AppEnvironment,
        registersForPushNotifications: Bool = true,
        deferBackendInitialization: Bool = false,
        persistInboxOnReady: Bool = true
    ) -> AuthorizeInboxOperation {
        let operation = AuthorizeInboxOperation(
            databaseReader: databaseReader,
            databaseWriter: databaseWriter,
            environment: environment,
            shouldStartStreamingServicesOnReady: true,
            registersForPushNotifications: registersForPushNotifications,
            deferBackendInitialization: deferBackendInitialization,
            persistInboxOnReady: persistInboxOnReady
        )
        operation.register()
        return operation
    }

    private init(
        databaseReader: any DatabaseReader,
        databaseWriter: any DatabaseWriter,
        environment: AppEnvironment,
        shouldStartStreamingServicesOnReady: Bool,
        registersForPushNotifications: Bool,
        deferBackendInitialization: Bool,
        persistInboxOnReady: Bool
    ) {
        let inboxWriter = InboxWriter(databaseWriter: databaseWriter)
        let syncingManager = SyncingManager(databaseWriter: databaseWriter)
        let inviteJoinRequestsManager = InviteJoinRequestsManager(
            databaseReader: databaseReader,
            databaseWriter: databaseWriter
        )
        stateMachine = InboxStateMachine(
            identityStore: environment.defaultIdentityStore,
            inboxWriter: inboxWriter,
            syncingManager: syncingManager,
            inviteJoinRequestsManager: inviteJoinRequestsManager,
            pushNotificationRegistrar: PushNotificationRegistrar(
                environment: environment
            ),
            autoRegistersForPushNotifications: registersForPushNotifications,
            environment: environment,
            shouldStartStreamingServicesOnReady: shouldStartStreamingServicesOnReady,
            deferBackendInitialization: deferBackendInitialization,
            persistInboxOnReady: persistInboxOnReady
        )
    }

    deinit {
        task?.cancel()
        task = nil
    }

    private func authorize(inboxId: String) {
        task?.cancel()
        task = Task { [weak self] in
            guard let self else { return }
            await stateMachine.authorize(inboxId: inboxId)
        }
    }

    private func register() {
        task?.cancel()
        task = Task { [weak self] in
            guard let self else { return }
            await stateMachine.register()
        }
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

    func activateDeferredInbox(registersForPushNotifications: Bool) async {
        await stateMachine.activateDeferredInbox(registersForPushNotifications: registersForPushNotifications)
    }
}
