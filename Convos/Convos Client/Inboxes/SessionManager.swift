import Combine
import Foundation
import GRDB

typealias AnyMessagingService = any MessagingServiceProtocol
typealias AnyMessagingServicePublisher = AnyPublisher<AnyMessagingService, Never>
typealias AnyClientProvider = any XMTPClientProvider
typealias AnyClientProviderPublisher = AnyPublisher<AnyClientProvider, Never>

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
    private let authService: any AuthServiceProtocol
    private let localAuthService: any LocalAuthServiceProtocol
    private let environment: AppEnvironment

    init(authService: any AuthServiceProtocol,
         localAuthService: any LocalAuthServiceProtocol,
         databaseWriter: any DatabaseWriter,
         databaseReader: any DatabaseReader,
         environment: AppEnvironment) {
        self.databaseWriter = databaseWriter
        self.databaseReader = databaseReader
        self.inboxesRepository = InboxesRepository(databaseReader: databaseReader)
        self.authService = authService
        self.localAuthService = localAuthService
        self.environment = environment
        let currentSessionRepository = CurrentSessionRepository(dbReader: databaseReader)
        self.currentSessionRepository = currentSessionRepository
        self.authState = authService.authStatePublisher
            .merge(with: localAuthService.authStatePublisher)
            .eraseToAnyPublisher()
        authState
            .sink { [weak self] authState in
                self?.handleAuthStateChange(authState)
            }
            .store(in: &cancellables)
    }

    // MARK: - Private Methods

    private func handleAuthStateChange(_ authState: AuthServiceState) {
        Logger.info("Auth state changed: \(authState)")

        switch authState {
        case .authorized(let authResult):
            updateOperationsForInboxes(authResult.inboxes, isRegistration: false)
        case .registered(let registeredResult):
            updateOperationsForInboxes(
                registeredResult.inboxes,
                isRegistration: true,
                displayName: registeredResult.displayName
            )
        case .unauthorized, .migrating, .notReady, .unknown:
            clearAllOperations()
        }
    }

    private func updateOperationsForInboxes(
        _ inboxes: [any AuthServiceInboxType],
        isRegistration: Bool,
        displayName: String? = nil
    ) {
        // Get current inbox IDs from the new auth state
        let currentInboxIds = Set(inboxes.map { $0.signingKey.identity.identifier })

        // Stop and remove operations for inboxes that are no longer present
        let operationsToRemove = operationsByInboxId.keys.filter { !currentInboxIds.contains($0) }
        for inboxId in operationsToRemove {
            operationsByInboxId[inboxId]?.stop()
            operationsByInboxId.removeValue(forKey: inboxId)
        }

        // Create or update operations for current inboxes
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

            // Start the operation based on whether it's registration or authorization
            if isRegistration {
                operationsByInboxId[inboxId]?.register(displayName: displayName ?? "User")
            } else {
                operationsByInboxId[inboxId]?.authorize()
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
        try localAuthService.prepare()
        try authService.prepare()
    }

    func addAccount() async throws {
        guard let accountsService = authService.accountsService else {
            Logger.info("Accounts service not available.")
            return
        }

        let result = try await accountsService.addAccount(displayName: "User")
        Logger.info("Added account: \(result)")
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
