import Combine
import Foundation
import GRDB

protocol AuthorizeInboxOperationProtocol {
    func stopAndDelete()
    func stop()
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
        registersForPushNotifications: Bool = false
    ) -> AuthorizeInboxOperation {
        let operation = AuthorizeInboxOperation(
            databaseReader: databaseReader,
            databaseWriter: databaseWriter,
            environment: environment,
            registersForPushNotifications: registersForPushNotifications
        )
        operation.authorize(inboxId: inboxId)
        return operation
    }

    static func register(
        databaseReader: any DatabaseReader,
        databaseWriter: any DatabaseWriter,
        environment: AppEnvironment,
        registersForPushNotifications: Bool = false
    ) -> AuthorizeInboxOperation {
        let operation = AuthorizeInboxOperation(
            databaseReader: databaseReader,
            databaseWriter: databaseWriter,
            environment: environment,
            registersForPushNotifications: registersForPushNotifications
        )
        operation.register()
        return operation
    }

    private init(
        databaseReader: any DatabaseReader,
        databaseWriter: any DatabaseWriter,
        environment: AppEnvironment,
        registersForPushNotifications: Bool = false
    ) {
        let inboxWriter = InboxWriter(databaseWriter: databaseWriter)

        // Create push notification registrar only if not in notification service extension
        let pushNotificationRegistrar: PushNotificationRegistrarProtocol? = registersForPushNotifications ? PushNotificationRegistrar(
            environment: environment
        ) : nil

        stateMachine = InboxStateMachine(
            inboxWriter: inboxWriter,
            syncingManager: SyncingManager(databaseWriter: databaseWriter),
            inviteJoinRequestsManager: InviteJoinRequestsManager(
                databaseReader: databaseReader,
                databaseWriter: databaseWriter
            ),
            pushNotificationRegistrar: pushNotificationRegistrar,
            environment: environment,
        )
    }

    deinit {
        task?.cancel()
        task = nil
    }

    private func authorize(inboxId: String) {
        task?.cancel()
        task = Task { [stateMachine] in
            await stateMachine.authorize(inboxId: inboxId)
        }
    }

    private func register() {
        task?.cancel()
        task = Task { [stateMachine] in
            await stateMachine.register()
        }
    }

    func stopAndDelete() {
        task?.cancel()
        task = Task { [stateMachine] in
            await stateMachine.stopAndDelete()
        }
    }

    func stop() {
        task?.cancel()
        task = Task { [stateMachine] in
            await stateMachine.stop()
        }
    }
}
