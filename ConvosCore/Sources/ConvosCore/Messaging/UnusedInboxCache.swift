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
        Task(priority: .background) {
            await createNewUnusedInbox(
                databaseWriter: databaseWriter,
                databaseReader: databaseReader,
                environment: environment
            )
        }
    }

    /// Clears any cached unused inbox and prevents it from being used.
    /// - Note: This also clears the "unused inbox" keychain item so the next app start won't reuse it.
    func reset() async {
        // Best-effort stop and drop any in-memory unused service
        if let service = unusedMessagingService {
            await service.stopAndDelete()
        }
        unusedMessagingService = nil
        clearUnusedInboxFromKeychain()
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

            // Schedule creation of a new unused inbox for next time
            Task(priority: .background) {
                await createNewUnusedInbox(
                    databaseWriter: databaseWriter,
                    databaseReader: databaseReader,
                    environment: environment
                )
            }

            await unusedService.registerForPushNotifications()

            return unusedService
        }

        // Check for an unused inbox ID in keychain (fallback)
        if let unusedInboxId = getUnusedInboxFromKeychain() {
            Logger.info("Using unused inbox ID from keychain: \(unusedInboxId)")

            // Clear from keychain
            clearUnusedInboxFromKeychain()

            // Schedule creation of a new unused inbox for next time
            Task(priority: .background) {
                await createNewUnusedInbox(
                    databaseWriter: databaseWriter,
                    databaseReader: databaseReader,
                    environment: environment
                )
            }

            // Use the existing inbox with authorize
            let authorizationOperation = AuthorizeInboxOperation.authorize(
                inboxId: unusedInboxId,
                databaseReader: databaseReader,
                databaseWriter: databaseWriter,
                environment: environment,
                startsStreamingServices: true,
                registersForPushNotifications: true
            )
            return MessagingService(
                inboxId: unusedInboxId,
                authorizationOperation: authorizationOperation,
                databaseWriter: databaseWriter,
                databaseReader: databaseReader
            )
        }

        // No unused inbox available, create a new one
        Logger.info("No unused inbox available, creating new one")

        // Schedule creation of an unused inbox for next time
        Task(priority: .background) {
            await createNewUnusedInbox(
                databaseWriter: databaseWriter,
                databaseReader: databaseReader,
                environment: environment
            )
        }

        // Create and return a new messaging service
        let authorizationOperation = AuthorizeInboxOperation.register(
            databaseReader: databaseReader,
            databaseWriter: databaseWriter,
            environment: environment,
            registersForPushNotifications: true
        )

        return MessagingService(
            inboxId: nil,
            authorizationOperation: authorizationOperation,
            databaseWriter: databaseWriter,
            databaseReader: databaseReader
        )
    }

    // MARK: - Private Methods

    private func authorizeUnusedInbox(
        inboxId: String,
        databaseWriter: any DatabaseWriter,
        databaseReader: any DatabaseReader,
        environment: AppEnvironment
    ) async {
        let authorizationOperation = AuthorizeInboxOperation.authorize(
            inboxId: inboxId,
            databaseReader: databaseReader,
            databaseWriter: databaseWriter,
            environment: environment,
            startsStreamingServices: false,
            registersForPushNotifications: false,
            deferBackendInitialization: true,
            persistInboxOnReady: false
        )

        let messagingService = MessagingService(
            inboxId: inboxId,
            authorizationOperation: authorizationOperation,
            databaseWriter: databaseWriter,
            databaseReader: databaseReader
        )

        do {
            // Wait for it to be ready
            _ = try await messagingService.inboxStateManager.waitForInboxReadyResult()

            // Store it as the unused messaging service
            unusedMessagingService = messagingService

            Logger.info("Successfully authorized unused inbox (deferred): \(inboxId)")
        } catch {
            Logger.error("Failed to authorize unused inbox: \(error)")
            // Clear the invalid inbox ID from keychain
            clearUnusedInboxFromKeychain()
            // Clean up the messaging service
            await messagingService.stopAndDelete()

            // Create a new unused inbox
            Task(priority: .background) {
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

        let authorizationOperation = AuthorizeInboxOperation.register(
            databaseReader: databaseReader,
            databaseWriter: databaseWriter,
            environment: environment,
            registersForPushNotifications: false,
            deferBackendInitialization: true,
            persistInboxOnReady: false
        )

        let tempMessagingService = MessagingService(
            inboxId: nil,
            authorizationOperation: authorizationOperation,
            databaseWriter: databaseWriter,
            databaseReader: databaseReader
        )

        do {
            let result = try await tempMessagingService.inboxStateManager.waitForInboxReadyResult()
            let inboxId = result.client.inboxId

            // Save the inbox ID to keychain
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
