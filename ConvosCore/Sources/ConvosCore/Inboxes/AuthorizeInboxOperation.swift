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
    private let taskLock: NSLock = NSLock()
    private var _task: Task<Void, Never>?

    private var task: Task<Void, Never>? {
        get {
            taskLock.lock()
            defer { taskLock.unlock() }
            return _task
        }
        set {
            taskLock.lock()
            defer { taskLock.unlock() }
            _task = newValue
        }
    }

    // swiftlint:disable:next function_parameter_count
    static func authorize(
        inboxId: String,
        clientId: String,
        identityStore: any KeychainIdentityStoreProtocol,
        databaseReader: any DatabaseReader,
        databaseWriter: any DatabaseWriter,
        environment: AppEnvironment,
        startsStreamingServices: Bool,
        deviceRegistrationManager: (any DeviceRegistrationManagerProtocol)? = nil,
        overrideJWTToken: String? = nil
    ) -> AuthorizeInboxOperation {
        let operation = AuthorizeInboxOperation(
            clientId: clientId,
            identityStore: identityStore,
            databaseReader: databaseReader,
            databaseWriter: databaseWriter,
            environment: environment,
            startsStreamingServices: startsStreamingServices,
            deviceRegistrationManager: deviceRegistrationManager,
            overrideJWTToken: overrideJWTToken
        )
        operation.authorize(inboxId: inboxId, clientId: clientId)
        return operation
    }

    static func register(
        identityStore: any KeychainIdentityStoreProtocol,
        databaseReader: any DatabaseReader,
        databaseWriter: any DatabaseWriter,
        environment: AppEnvironment,
        deviceRegistrationManager: (any DeviceRegistrationManagerProtocol)? = nil,
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
            deviceRegistrationManager: deviceRegistrationManager,
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
        deviceRegistrationManager: (any DeviceRegistrationManagerProtocol)? = nil,
        savesInboxToDatabase: Bool = true,
        overrideJWTToken: String? = nil
    ) {
        let syncingManager = startsStreamingServices ? SyncingManager(
            identityStore: identityStore,
            databaseWriter: databaseWriter,
            databaseReader: databaseReader,
            deviceRegistrationManager: deviceRegistrationManager
        ) : nil
        let invitesRepository = InvitesRepository(databaseReader: databaseReader)
        stateMachine = InboxStateMachine(
            clientId: clientId,
            identityStore: identityStore,
            invitesRepository: invitesRepository,
            databaseWriter: databaseWriter,
            syncingManager: syncingManager,
            savesInboxToDatabase: savesInboxToDatabase,
            overrideJWTToken: overrideJWTToken,
            environment: environment
        )
    }

    deinit {
        cancelAndReplaceTask(with: nil)
    }

    /// Atomically cancels the current task and replaces it with a new one
    private func cancelAndReplaceTask(with newTask: Task<Void, Never>?) {
        taskLock.lock()
        defer { taskLock.unlock() }
        _task?.cancel()
        _task = newTask
    }

    private func authorize(inboxId: String, clientId: String) {
        let newTask = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            await stateMachine.authorize(inboxId: inboxId, clientId: clientId)
        }
        cancelAndReplaceTask(with: newTask)
    }

    private func register(clientId: String) {
        let newTask = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            await stateMachine.register(clientId: clientId)
        }
        cancelAndReplaceTask(with: newTask)
    }

    func stopAndDelete() {
        let newTask = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            await stateMachine.stopAndDelete()
        }
        cancelAndReplaceTask(with: newTask)
    }

    func stopAndDelete() async {
        cancelAndReplaceTask(with: nil)
        await stateMachine.stopAndDelete()
    }

    func stop() {
        let newTask = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            await stateMachine.stop()
        }
        cancelAndReplaceTask(with: newTask)
    }
}
