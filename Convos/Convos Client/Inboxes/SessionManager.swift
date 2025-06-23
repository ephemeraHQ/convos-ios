import Combine
import Foundation
import GRDB

enum SessionManagerError: Error {
    case noSuchMessagingService(String)
}

class SessionManager: SessionManagerProtocol {
    let inboxesRepository: any InboxesRepositoryProtocol
    private let inboxOperationsPublisher: CurrentValueSubject<[any AuthorizeInboxOperationProtocol], Never> = .init([])
    private var inboxOperationsCancellable: AnyCancellable

    private let databaseWriter: any DatabaseWriter
    private let databaseReader: any DatabaseReader
    private var cancellables: Set<AnyCancellable> = []
    private let authService: any AuthServiceProtocol
    private let environment: AppEnvironment

    init(authService: any AuthServiceProtocol,
         databaseWriter: any DatabaseWriter,
         databaseReader: any DatabaseReader,
         environment: AppEnvironment) {
        self.databaseWriter = databaseWriter
        self.databaseReader = databaseReader
        self.inboxesRepository = InboxesRepository(databaseReader: databaseReader)
        self.authService = authService
        self.environment = environment
        inboxOperationsCancellable = authService
            .authStatePublisher
            .sink { [inboxOperationsPublisher] authState in
                Logger.info("Auth state changed: \(authState)")
                switch authState {
                case .authorized(let authResult):
                    let operations = authResult.inboxes.map { inbox in
                        let operation = AuthorizeInboxOperation(
                            inbox: inbox,
                            databaseReader: databaseReader,
                            databaseWriter: databaseWriter,
                            environment: environment
                        )
                        operation.authorize()
                        return operation
                    }
                    inboxOperationsPublisher.send(operations)
                case .registered(let registeredResult):
                    let operations = registeredResult.inboxes.map { inbox in
                        let operation = AuthorizeInboxOperation(
                            inbox: inbox,
                            databaseReader: databaseReader,
                            databaseWriter: databaseWriter,
                            environment: environment
                        )
                        operation.register(displayName: registeredResult.displayName)
                        return operation
                    }
                    inboxOperationsPublisher.send(operations)
                case .unauthorized, .migrating, .notReady, .unknown:
                    inboxOperationsPublisher.send([])
                }
            }
    }

    // MARK: Messaging

    func messagingServicePublisher(for inboxId: String) -> AnyPublisher<any MessagingServiceProtocol, Never> {
        return inboxOperationsPublisher
            .flatMap { operations -> AnyPublisher<any MessagingServiceProtocol, Never> in
                let operation = operations.first(where: { operation in
                    switch operation.state {
                    case .ready(let client, _):
                        return client.inboxId == inboxId
                    default:
                        return false
                    }
                })

                guard let operation else {
                    return Empty().eraseToAnyPublisher()
                }

                return operation.messagingPublisher
            }
            .eraseToAnyPublisher()
    }

    // MARK: Displaying All Conversations

    func conversationsRepository(for consent: [Consent]) -> any ConversationsRepositoryProtocol {
        ConversationsRepository(dbReader: databaseReader, consent: consent)
    }

    func conversationsCountRepo(for consent: [Consent]) -> any ConversationsCountRepositoryProtocol {
        ConversationsCountRepository(databaseReader: databaseReader, consent: consent)
    }
}
