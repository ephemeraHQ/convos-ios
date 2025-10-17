import Foundation
import GRDB

/// Manages pre-created unused inboxes for faster user onboarding
actor UnusedInboxCache {
    static let shared: UnusedInboxCache = .init()

    // MARK: - Properties

    private let keychainService: KeychainService<UnusedInboxKeychainItem>
    private var unusedMessagingService: MessagingService?
    private var isCreatingUnusedInbox: Bool = false

    // MARK: - Initialization

    private init() {
        self.keychainService = KeychainService<UnusedInboxKeychainItem>()
    }

    // MARK: - Public Methods

    /// Checks if an unused inbox is available and prepares one if needed
    func prepareUnusedInboxIfNeeded(
        databaseWriter: any DatabaseWriter,
        databaseReader: any DatabaseReader,
        environment: AppEnvironment
    ) async {
        // Check if we already have an unused messaging service ready
        if unusedMessagingService != nil {
            Logger.debug("Unused messaging service already exists")
            return
        }

        // Check if we have an unused inbox ID in keychain
        if let unusedInboxId = getUnusedInboxFromKeychain() {
            Logger.info("Found unused inbox ID in keychain: \(unusedInboxId)")
            await authorizeUnusedInbox(
                inboxId: unusedInboxId,
                databaseWriter: databaseWriter,
                databaseReader: databaseReader,
                environment: environment
            )
            return
        }

        // No unused inbox exists, create a new one
        Logger.info("No unused inbox found, creating new one")
        Task(priority: .background) { [weak self] in
            guard let self else { return }
            await createNewUnusedInbox(
                databaseWriter: databaseWriter,
                databaseReader: databaseReader,
                environment: environment
            )
        }
    }

    /// Consumes the unused inbox if available, or creates a new one
    func consumeOrCreateMessagingService(
        databaseWriter: any DatabaseWriter,
        databaseReader: any DatabaseReader,
        environment: AppEnvironment
    ) async -> MessagingService {
        // Check if we have a pre-created unused messaging service
        if let unusedService = unusedMessagingService {
            Logger.info("Using pre-created unused messaging service")

            // Clear the reference
            unusedMessagingService = nil

            // Clear from keychain
            clearUnusedInboxFromKeychain()

            // Save to database now that it's being consumed by the user
            do {
                let result = try await unusedService.inboxStateManager.waitForInboxReadyResult()
                let inboxId = result.client.inboxId
                let identity = try await environment.defaultIdentityStore.identity(for: inboxId)
                let inboxWriter = InboxWriter(dbWriter: databaseWriter)
                try await inboxWriter.save(inboxId: inboxId, clientId: identity.clientId)
                Logger.info("Saved consumed unused inbox to database: \(inboxId)")
            } catch {
                Logger.error("Failed to save consumed inbox to database: \(error)")
            }

            // Schedule creation of a new unused inbox for next time
            Task(priority: .background) { [weak self] in
                guard let self else { return }
                await createNewUnusedInbox(
                    databaseWriter: databaseWriter,
                    databaseReader: databaseReader,
                    environment: environment
                )
            }

            // Device registration happens automatically when inbox becomes ready
            return unusedService
        }

        // Check for an unused inbox ID in keychain (fallback)
        if let unusedInboxId = getUnusedInboxFromKeychain() {
            Logger.info("Using unused inbox ID from keychain: \(unusedInboxId)")

            // Clear from keychain
            clearUnusedInboxFromKeychain()

            // Schedule creation of a new unused inbox for next time
            Task(priority: .background) { [weak self] in
                guard let self else { return }
                await createNewUnusedInbox(
                    databaseWriter: databaseWriter,
                    databaseReader: databaseReader,
                    environment: environment
                )
            }

            // Use the existing inbox with authorize
            // Note: The authorize flow in InboxStateMachine.handleAuthorize() will
            // automatically save this inbox to the database
            let identityStore = environment.defaultIdentityStore
            let authorizationOperation = AuthorizeInboxOperation.authorize(
                inboxId: unusedInboxId,
                identityStore: identityStore,
                databaseReader: databaseReader,
                databaseWriter: databaseWriter,
                environment: environment,
                startsStreamingServices: true
            )
            return MessagingService(
                authorizationOperation: authorizationOperation,
                databaseWriter: databaseWriter,
                databaseReader: databaseReader,
                identityStore: identityStore
            )
        }

        // No unused inbox available, create a new one
        Logger.info("No unused inbox available, creating new one")

        // Schedule creation of an unused inbox for next time
        Task(priority: .background) { [weak self] in
            guard let self else { return }
            await createNewUnusedInbox(
                databaseWriter: databaseWriter,
                databaseReader: databaseReader,
                environment: environment
            )
        }

        // Create and return a new messaging service
        let identityStore = environment.defaultIdentityStore
        let authorizationOperation = AuthorizeInboxOperation.register(
            identityStore: identityStore,
            databaseReader: databaseReader,
            databaseWriter: databaseWriter,
            environment: environment
        )

        return MessagingService(
            authorizationOperation: authorizationOperation,
            databaseWriter: databaseWriter,
            databaseReader: databaseReader,
            identityStore: identityStore
        )
    }

    // MARK: - Private Methods

    private func authorizeUnusedInbox(
        inboxId: String,
        databaseWriter: any DatabaseWriter,
        databaseReader: any DatabaseReader,
        environment: AppEnvironment
    ) async {
        let identityStore = environment.defaultIdentityStore
        let authorizationOperation = AuthorizeInboxOperation.authorize(
            inboxId: inboxId,
            identityStore: identityStore,
            databaseReader: databaseReader,
            databaseWriter: databaseWriter,
            environment: environment,
            startsStreamingServices: true
        )

        let messagingService = MessagingService(
            authorizationOperation: authorizationOperation,
            databaseWriter: databaseWriter,
            databaseReader: databaseReader,
            identityStore: identityStore
        )

        do {
            // Wait for it to be ready
            _ = try await messagingService.inboxStateManager.waitForInboxReadyResult()

            // Store it as the unused messaging service
            unusedMessagingService = messagingService

            Logger.info("Successfully authorized unused inbox: \(inboxId)")
        } catch {
            Logger.error("Failed to authorize unused inbox: \(error)")
            // Clear the invalid inbox ID from keychain
            clearUnusedInboxFromKeychain()
            // Clean up the messaging service
            await messagingService.stopAndDelete()

            // Create a new unused inbox
            Task(priority: .background) { [weak self] in
                guard let self else { return }
                await createNewUnusedInbox(
                    databaseWriter: databaseWriter,
                    databaseReader: databaseReader,
                    environment: environment
                )
            }
        }
    }

    private func createNewUnusedInbox(
        databaseWriter: any DatabaseWriter,
        databaseReader: any DatabaseReader,
        environment: AppEnvironment
    ) async {
        guard unusedMessagingService == nil else {
            Logger.debug("Unused messaging service exists, skipping creating new unused inbox...")
            return
        }

        guard !isCreatingUnusedInbox else {
            Logger.debug("Already creating unused inbox, skipping")
            return
        }

        isCreatingUnusedInbox = true
        defer { isCreatingUnusedInbox = false }

        Logger.info("Creating new unused inbox in background")

        let identityStore = environment.defaultIdentityStore
        let authorizationOperation = AuthorizeInboxOperation.register(
            identityStore: identityStore,
            databaseReader: databaseReader,
            databaseWriter: databaseWriter,
            environment: environment,
            savesInboxToDatabase: false
        )

        let tempMessagingService = MessagingService(
            authorizationOperation: authorizationOperation,
            databaseWriter: databaseWriter,
            databaseReader: databaseReader,
            identityStore: identityStore
        )

        do {
            let result = try await tempMessagingService.inboxStateManager.waitForInboxReadyResult()
            let inboxId = result.client.inboxId

            // Save the inbox ID to keychain, save to database when consumed
            saveUnusedInboxToKeychain(inboxId)

            // Store the messaging service instance
            unusedMessagingService = tempMessagingService

            Logger.info("Successfully created unused inbox: \(inboxId)")
        } catch {
            Logger.error("Failed to create unused inbox: \(error)")
            // Clean up on error
            await tempMessagingService.stopAndDelete()
        }
    }

    // MARK: - Keychain Helpers

    private func getUnusedInboxFromKeychain() -> String? {
        do {
            return try keychainService.retrieveString(UnusedInboxKeychainItem())
        } catch {
            Logger.debug("No unused inbox found in keychain: \(error)")
            return nil
        }
    }

    private func saveUnusedInboxToKeychain(_ inboxId: String) {
        do {
            try keychainService.saveString(inboxId, for: UnusedInboxKeychainItem())
            Logger.info("Saved unused inbox to keychain: \(inboxId)")
        } catch {
            Logger.error("Failed to save unused inbox to keychain: \(error)")
        }
    }

    private func clearUnusedInboxFromKeychain() {
        do {
            try keychainService.delete(UnusedInboxKeychainItem())
            Logger.debug("Cleared unused inbox from keychain")
        } catch {
            Logger.debug("Failed to clear unused inbox from keychain: \(error)")
        }
    }
}
