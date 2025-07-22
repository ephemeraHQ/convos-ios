import Combine
import Foundation
import GRDB

typealias AnyMessagingService = any MessagingServiceProtocol
typealias AnyMessagingServicePublisher = AnyPublisher<AnyMessagingService, Never>
typealias AnyClientProvider = any XMTPClientProvider
typealias AnyClientProviderPublisher = AnyPublisher<AnyClientProvider, Never>

enum SessionManagerError: Error {
    case missingOperationForAddedInbox
}

class SessionManager: SessionManagerProtocol {
    let authState: AnyPublisher<AuthServiceState, Never>
    let inboxesRepository: any InboxesRepositoryProtocol
    private let currentSessionRepository: any CurrentSessionRepositoryProtocol
    private let inboxOperationsPublisher: CurrentValueSubject<[any AuthorizeInboxOperationProtocol], Never> = .init([])
    private var cancellables: Set<AnyCancellable> = []

    // Dictionary to track operations by inbox ID to prevent duplicates
    private var operationsByInboxId: [String: any AuthorizeInboxOperationProtocol] = [:]

    private let databaseWriter: any DatabaseWriter
    private let databaseReader: any DatabaseReader
    private let authService: any LocalAuthServiceProtocol
    private let environment: AppEnvironment

    init(authService: any LocalAuthServiceProtocol,
         databaseWriter: any DatabaseWriter,
         databaseReader: any DatabaseReader,
         environment: AppEnvironment) {
        self.databaseWriter = databaseWriter
        self.databaseReader = databaseReader
        self.inboxesRepository = InboxesRepository(databaseReader: databaseReader)
        self.authService = authService
        self.environment = environment
        let currentSessionRepository = CurrentSessionRepository(dbReader: databaseReader)
        self.currentSessionRepository = currentSessionRepository
        self.authState = authService.authStatePublisher
            .eraseToAnyPublisher()
        authState
            .sink { [weak self] authState in
                do {
                    try self?.handleAuthStateChange(authState)
                } catch {
                    Logger.error("Error handling auth state change: \(authState)")
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Private Methods

    private func handleAuthStateChange(_ authState: AuthServiceState) throws {
        Logger.info("Auth state changed: \(authState)")

        switch authState {
        case .authorized(let authResult):
            try updateOperations(for: authResult.inboxes, forRegistration: false)
        case .registered(let registeredResult):
            try updateOperations(
                for: registeredResult.inboxes,
                forRegistration: true,
                displayName: registeredResult.displayName
            )
        case .unauthorized, .notReady, .unknown:
            clearAllOperations()
        }
    }

    private func updateOperations(
        for inboxes: [any AuthServiceInboxType],
        forRegistration: Bool,
        displayName: String? = nil
    ) throws {
        // Create or update operations for inboxes
        for inbox in inboxes {
            let inboxId = inbox.signingKey.identity.identifier

            // Create new operation if it doesn't exist
            if operationsByInboxId[inboxId] == nil {
                let operation = AuthorizeInboxOperation(
                    inbox: inbox,
                    databaseReader: databaseReader,
                    databaseWriter: databaseWriter,
                    environment: environment
                )
                operationsByInboxId[inboxId] = operation
            }

            guard let operation = operationsByInboxId[inboxId] else {
                throw SessionManagerError.missingOperationForAddedInbox
            }

            if forRegistration {
                operation.register(displayName: displayName)
            } else {
                operation.authorize()
            }
        }

        // Update the publisher with current operations
        inboxOperationsPublisher.send(Array(operationsByInboxId.values))
    }

    private func clearAllOperations() {
        // Stop all existing operations
        for operation in operationsByInboxId.values {
            operation.stop()
        }

        // Clear the dictionary and publisher
        operationsByInboxId.removeAll()
        inboxOperationsPublisher.send([])
    }

    func prepare() throws {
        try authService.prepare()
    }

    func addAccount() throws -> AnyMessagingService {
        let authResult = try authService.register(displayName: nil)
        Logger.info("Added account: \(authResult)")
        let matchingInboxReadyPublisher = inboxOperationsPublisher
            .flatMap { operations in
                Publishers.MergeMany(
                    operations.map { $0.inboxReadyPublisher }
                )
            }
            .first { result in
                result.inbox.providerId == authResult.inbox.providerId
            }
            .eraseToAnyPublisher()
        return MessagingService(
            inboxReadyPublisher: matchingInboxReadyPublisher,
            databaseWriter: databaseWriter,
            databaseReader: databaseReader
        )
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
