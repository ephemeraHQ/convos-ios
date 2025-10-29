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
}

final class AuthorizeInboxOperation: AuthorizeInboxOperationProtocol {
    let stateMachine: InboxStateMachine
    private var cancellables: Set<AnyCancellable> = []
    private var task: Task<Void, Never>?

    // swiftlint:disable:next function_parameter_count
    static func authorize(
        inboxId: String,
        clientId: String,
        identityStore: any KeychainIdentityStoreProtocol,
        databaseReader: any DatabaseReader,
        databaseWriter: any DatabaseWriter,
        environment: AppEnvironment,
        startsStreamingServices: Bool,
        isNSEContext: Bool = false
    ) -> AuthorizeInboxOperation {
        let operation = AuthorizeInboxOperation(
            clientId: clientId,
            identityStore: identityStore,
            databaseReader: databaseReader,
            databaseWriter: databaseWriter,
            environment: environment,
            startsStreamingServices: startsStreamingServices,
            isNSEContext: isNSEContext
        )
        operation.authorize(inboxId: inboxId, clientId: clientId)
        return operation
    }

    static func register(
        identityStore: any KeychainIdentityStoreProtocol,
        databaseReader: any DatabaseReader,
        databaseWriter: any DatabaseWriter,
        environment: AppEnvironment,
        savesInboxToDatabase: Bool = true
    ) -> AuthorizeInboxOperation {
        // Generate clientId before creating state machine
        let clientId = ClientId.generate().value
        let operation = AuthorizeInboxOperation(
            clientId: clientId,
            identityStore: identityStore,
            databaseReader: databaseReader,
            databaseWriter: databaseWriter,
            environment: environment,
            startsStreamingServices: true,
            savesInboxToDatabase: savesInboxToDatabase
        )
        operation.register(clientId: clientId)
        return operation
    }

    private init(
        clientId: String,
        identityStore: any KeychainIdentityStoreProtocol,
        databaseReader: any DatabaseReader,
        databaseWriter: any DatabaseWriter,
        environment: AppEnvironment,
        startsStreamingServices: Bool,
        savesInboxToDatabase: Bool = true,
        isNSEContext: Bool = false
    ) {
        let syncingManager = startsStreamingServices ? SyncingManager(
            identityStore: identityStore,
            databaseWriter: databaseWriter,
            databaseReader: databaseReader
        ) : nil
        let invitesRepository = InvitesRepository(databaseReader: databaseReader)
        stateMachine = InboxStateMachine(
            clientId: clientId,
            identityStore: identityStore,
            invitesRepository: invitesRepository,
            databaseWriter: databaseWriter,
            syncingManager: syncingManager,
            savesInboxToDatabase: savesInboxToDatabase,
            isNSEContext: isNSEContext,
            environment: environment
        )
    }

    deinit {
        task?.cancel()
        task = nil
    }

    private func authorize(inboxId: String, clientId: String) {
        task?.cancel()
        task = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            await stateMachine.authorize(inboxId: inboxId, clientId: clientId)
        }
    }

    private func register(clientId: String) {
        task?.cancel()
        task = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            await stateMachine.register(clientId: clientId)
        }
    }

    func stopAndDelete() {
        task?.cancel()
        task = Task(priority: .userInitiated) { [weak self] in
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
        task = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            await stateMachine.stop()
        }
    }
}
