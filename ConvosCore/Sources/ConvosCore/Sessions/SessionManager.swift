import Combine
import Foundation
import GRDB

public extension Notification.Name {
    static let leftConversationNotification: Notification.Name = Notification.Name("LeftConversationNotification")
}

public typealias AnyMessagingService = any MessagingServiceProtocol
public typealias AnyMessagingServicePublisher = AnyPublisher<AnyMessagingService, Never>
public typealias AnyClientProvider = any XMTPClientProvider
public typealias AnyClientProviderPublisher = AnyPublisher<AnyClientProvider, Never>

enum SessionManagerError: Error {
    case missingOperationForAddedInbox
    case inboxNotFound
}

class SessionManager: SessionManagerProtocol {
    let authState: AnyPublisher<AuthServiceState, Never>
    private let currentSessionRepository: any CurrentSessionRepositoryProtocol
    private let inboxOperationsPublisher: CurrentValueSubject<[any AuthorizeInboxOperationProtocol], Never> = .init([])
    private var cancellables: Set<AnyCancellable> = []
    private var leftConversationObserver: Any?

    // Dictionary to track operations by provider ID to prevent duplicates
    private var operationsByProviderId: [String: any AuthorizeInboxOperationProtocol] = [:]

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
        self.authService = authService
        self.environment = environment
        let currentSessionRepository = CurrentSessionRepository(dbReader: databaseReader)
        self.currentSessionRepository = currentSessionRepository
        self.authState = authService.authStatePublisher
            .eraseToAnyPublisher()
        observe()
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

    deinit {
        if let leftConversationObserver {
            NotificationCenter.default.removeObserver(leftConversationObserver)
        }
        cleanup()
    }

    func cleanup() {
        cancellables.removeAll()
        clearAllOperations()
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
        // @jarodl revisit how we're responding to auth state changes
        if !forRegistration {
            let incomingProviderIds = Set(inboxes.map { $0.providerId })
            let providerIdsToRemove = operationsByProviderId.keys.filter { !incomingProviderIds.contains($0) }
            for providerId in providerIdsToRemove {
                Logger.info("Stopping inbox operation for provider: \(providerId)")
                if let operation = operationsByProviderId.removeValue(forKey: providerId) {
                    operation.stop()
                }
            }
        }

        // Create or update operations for inboxes
        for inbox in inboxes {
            let providerId = inbox.providerId

            // Create new operation if it doesn't exist
            if operationsByProviderId[providerId] == nil {
                let operation = AuthorizeInboxOperation(
                    inbox: inbox,
                    authService: authService,
                    databaseReader: databaseReader,
                    databaseWriter: databaseWriter,
                    environment: environment
                )
                operationsByProviderId[providerId] = operation

                if forRegistration {
                    operation.register(displayName: displayName)
                } else {
                    operation.authorize()
                }
            }
        }

        // Update the publisher with current operations
        inboxOperationsPublisher.send(Array(operationsByProviderId.values))
    }

    private func clearAllOperations() {
        // Stop all existing operations
        for operation in operationsByProviderId.values {
            operation.stop()
        }

        // Clear the dictionary and publisher
        operationsByProviderId.removeAll()
        inboxOperationsPublisher.send([])
    }

    private func observe() {
        leftConversationObserver = NotificationCenter.default
            .addObserver(forName: .leftConversationNotification, object: nil, queue: .main) { [weak self] notification in
                guard let self else { return }
                guard let inboxId: String = notification.userInfo?["inboxId"] as? String else {
                    return
                }
                do {
                    try deleteAccount(inboxId: inboxId)
                } catch {
                    Logger
                        .error(
                            "Error deleting account from left conversation notification: \(error.localizedDescription)"
                        )
                }
            }
    }

    // MARK: Public

    func prepare() throws {
        try authService.prepare()
    }

    func addAccount() throws -> AddAccountResultType {
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
        return .init(
            providerId: authResult.inbox.providerId,
            messagingService: MessagingService(
                inboxReadyPublisher: matchingInboxReadyPublisher,
                databaseWriter: databaseWriter,
                databaseReader: databaseReader
            )
        )
    }

    func deleteAccount(inboxId: String) throws {
        let inbox: DBInbox? = try databaseReader.read { db in
            try DBInbox.fetchOne(db, key: inboxId)
        }
        guard let inbox else {
            throw SessionManagerError.inboxNotFound
        }
        try deleteAccount(providerId: inbox.providerId)
    }

    func deleteAccount(providerId: String) throws {
        if let operation = operationsByProviderId[providerId] {
            operation.deleteAndStop()
        }
        try authService.deleteAccount(with: providerId)
    }

    func deleteAllAccounts() throws {
        // Ask all ready inbox state machines to unregister their installation before teardown
        NotificationCenter.default.post(name: .convosUnregisterAllInboxesRequested, object: nil)

        try authService.deleteAll()
        try databaseWriter.write { db in
            try DBInbox.deleteAll(db)
            try DBConversation.deleteAll(db)
            try DBConversationMember.deleteAll(db)
            try Member.deleteAll(db)
            try MemberProfile.deleteAll(db)
            try DBInvite.deleteAll(db)
            try DBMessage.deleteAll(db)
        }

        // Get the app group container URL
        let appGroupId = environment.appGroupIdentifier
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) else {
            Logger.error("Failed to get container URL for app group: \(appGroupId)")
            return
        }

        // List all files and directories in the app group container
        let fileManager = FileManager.default
        let contents = try fileManager.contentsOfDirectory(at: containerURL, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey])

        Logger.info("📁 App Group Container Contents (\(contents.count) items):")
        Logger.info("📍 Path: \(containerURL.path)")

        for url in contents {
            let resourceValues = try url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            let isDirectory = resourceValues.isDirectory ?? false
            let fileSize = resourceValues.fileSize ?? 0
            let fileName = url.lastPathComponent

            if isDirectory {
                Logger.info("📂 \(fileName)/")
            } else {
                let sizeString = ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
                Logger.info("📄 \(fileName) (\(sizeString))")
            }
        }

        // Delete specific XMTP files and salt files
        var deletedCount = 0

        for url in contents {
            let fileName = url.lastPathComponent

            // Delete XMTP database files and salt files
            if fileName.hasPrefix("xmtp-localhost-") || fileName.hasSuffix(".sqlcipher_salt") {
                do {
                    try fileManager.removeItem(at: url)
                    Logger.info("✅ Deleted: \(fileName)")
                    deletedCount += 1
                } catch {
                    Logger.error("❌ Failed to delete \(fileName): \(error)")
                }
            }
        }

        Logger.info("🧹 Deleted \(deletedCount) XMTP files")
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

    func conversationsCountRepo(for consent: [Consent], kinds: [ConversationKind]) -> any ConversationsCountRepositoryProtocol {
        ConversationsCountRepository(databaseReader: databaseReader, consent: consent, kinds: kinds)
    }
}
