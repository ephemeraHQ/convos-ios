import Combine
import Foundation
import GRDB

typealias AnyMessagingService = any MessagingServiceProtocol
typealias AnyMessagingServicePublisher = AnyPublisher<AnyMessagingService, Never>
typealias AnyClientProvider = any XMTPClientProvider
typealias AnyClientProviderPublisher = AnyPublisher<AnyClientProvider, Never>

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

    func messagingService(for inboxId: String) -> AnyMessagingService {
        let matchingInboxReadyPublisher = inboxOperationsPublisher
            .flatMap { operations in
                Publishers.MergeMany(
                    operations.map { $0.inboxReadyPublisher }
                )
            }
            .first { result in
                result.client.inboxId == inboxId
            }
            .eraseToAnyPublisher()
        return MessagingService(
            inboxReadyPublisher: matchingInboxReadyPublisher,
            databaseWriter: databaseWriter,
            databaseReader: databaseReader
        )
    }

    // MARK: Displaying All Conversations

    func conversationsRepository(for consent: [Consent]) -> any ConversationsRepositoryProtocol {
        ConversationsRepository(dbReader: databaseReader, consent: consent)
    }

    func conversationsCountRepo(for consent: [Consent]) -> any ConversationsCountRepositoryProtocol {
        ConversationsCountRepository(databaseReader: databaseReader, consent: consent)
    }
}
