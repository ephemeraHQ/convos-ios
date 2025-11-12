import Combine
import Foundation
import GRDB
import UserNotifications

public extension Notification.Name {
    static let leftConversationNotification: Notification.Name = Notification.Name("LeftConversationNotification")
    static let activeConversationChanged: Notification.Name = Notification.Name("ActiveConversationChanged")
}

public typealias AnyMessagingService = any MessagingServiceProtocol
public typealias AnyClientProvider = any XMTPClientProvider

enum SessionManagerError: Error {
    case inboxNotFound
}

/// Manages multiple inbox sessions and their lifecycle
///
/// SessionManager coordinates multiple MessagingService instances (one per inbox/identity),
/// handling their creation, lifecycle, and cleanup. It maintains thread-safe access to
/// active messaging services and provides factory methods for creating repositories.
/// The manager also handles inbox deletion, conversation notifications, and manages
/// the UnusedInboxCache for pre-creating inboxes.
public final class SessionManager: SessionManagerProtocol {
    private var leftConversationObserver: Any?
    private var activeConversationObserver: Any?

    // Thread-safe access to messaging services
    private let serviceQueue: DispatchQueue = DispatchQueue(label: "com.convos.sessionmanager.services")
    private var messagingServices: [String: AnyMessagingService] = [:] // Keyed by clientId
    private var activeConversationId: String?

    private let databaseWriter: any DatabaseWriter
    private let databaseReader: any DatabaseReader
    private let environment: AppEnvironment
    private let identityStore: any KeychainIdentityStoreProtocol
    private var initializationTask: Task<Void, Never>?
    private var unusedInboxPrepTask: Task<Void, Never>?
    private let deviceRegistrationManager: any DeviceRegistrationManagerProtocol
    private let unusedInboxCache: UnusedInboxCache

    init(databaseWriter: any DatabaseWriter,
         databaseReader: any DatabaseReader,
         environment: AppEnvironment,
         identityStore: any KeychainIdentityStoreProtocol,
         unusedInboxCache: UnusedInboxCache? = nil) {
        self.databaseWriter = databaseWriter
        self.databaseReader = databaseReader
        self.environment = environment
        self.identityStore = identityStore
        self.deviceRegistrationManager = DeviceRegistrationManager(environment: environment)
        self.unusedInboxCache = unusedInboxCache ?? UnusedInboxCache(
            identityStore: identityStore
        )
        observe()

        initializationTask = Task { [weak self] in
            guard let self else { return }
            guard !Task.isCancelled else { return }

            // Register device on app launch
            await self.deviceRegistrationManager.registerDeviceIfNeeded()
            guard !Task.isCancelled else { return }

            // Start observing push token changes for automatic re-registration
            await self.deviceRegistrationManager.startObservingPushTokenChanges()
            guard !Task.isCancelled else { return }

            do {
                let identities = try await identityStore.loadAll()
                guard !Task.isCancelled else { return }
                await self.startMessagingServices(for: identities)
            } catch {
                Log.error("Error starting messaging services: \(error.localizedDescription)")
            }
            guard !Task.isCancelled else { return }
            self.unusedInboxPrepTask = Task(priority: .background) { [weak self] in
                guard let self, !Task.isCancelled else { return }
                await self.unusedInboxCache.prepareUnusedInboxIfNeeded(
                    databaseWriter: self.databaseWriter,
                    databaseReader: self.databaseReader,
                    environment: self.environment
                )
            }
        }
    }

    deinit {
        initializationTask?.cancel()
        unusedInboxPrepTask?.cancel()
        if let leftConversationObserver {
            NotificationCenter.default.removeObserver(leftConversationObserver)
        }
        if let activeConversationObserver {
            NotificationCenter.default.removeObserver(activeConversationObserver)
        }
        messagingServices.removeAll()
    }

    // MARK: - Private Methods

    private func startMessagingServices(for identities: [KeychainIdentity]) async {
        let inboxIds = identities.map { $0.inboxId }
        Log.info("Starting messaging services for inboxes: \(inboxIds)")

        var servicesToCreate: [KeychainIdentity] = []

        await withTaskGroup(of: KeychainIdentity?.self) { group in
            for identity in identities {
                group.addTask { [weak self] in
                    guard let self else { return nil }
                    let isUnused = await self.unusedInboxCache.isUnusedInbox(identity.inboxId)
                    return isUnused ? nil : identity
                }
            }

            for await identity in group {
                if let identity {
                    servicesToCreate.append(identity)
                }
            }
        }

        serviceQueue.sync {
            for identity in servicesToCreate {
                let service = self.startMessagingService(for: identity.inboxId, clientId: identity.clientId)
                self.messagingServices[identity.clientId] = service
            }
        }
    }

    private func startMessagingService(for inboxId: String, clientId: String) -> AnyMessagingService {
        Log
            .info(
                "Starting messaging service for inboxId: \(inboxId) clientId: \(clientId)"
            )
        return MessagingService.authorizedMessagingService(
            for: inboxId,
            clientId: clientId,
            databaseWriter: databaseWriter,
            databaseReader: databaseReader,
            environment: environment,
            identityStore: identityStore,
            startsStreamingServices: true
        )
    }

    private func observe() {
        leftConversationObserver = NotificationCenter.default
            .addObserver(forName: .leftConversationNotification, object: nil, queue: .main) { notification in
                Task { [weak self] in
                    guard let self else { return }
                    guard let clientId = notification.userInfo?["clientId"] as? String,
                          let inboxId = notification.userInfo?["inboxId"] as? String else {
                        return
                    }

                    // Check if this is from an explosion (already handled in explodeConversation)
                    let conversationId = notification.userInfo?["conversationId"] as? String
                    if conversationId != nil {
                        // This is from explodeConversation, inbox already deleted
                        Log.info("Left conversation notification from explosion, inbox already handled")
                        return
                    }

                    do {
                        try await self.deleteInbox(clientId: clientId)
                    } catch {
                        Log.error("Error deleting inbox from left conversation notification: \(error.localizedDescription)")
                    }
                }
            }

        activeConversationObserver = NotificationCenter.default
            .addObserver(forName: .activeConversationChanged, object: nil, queue: .main) { [weak self] notification in
                guard let self else { return }
                let conversationId = notification.userInfo?["conversationId"] as? String
                self.setActiveConversationId(conversationId)
                Log.info("Active conversation changed to: \(conversationId ?? "none")")
            }
    }

    private func setActiveConversationId(_ conversationId: String?) {
        serviceQueue.sync {
            activeConversationId = conversationId
        }
    }

    // MARK: - Explosion Handling

    public func explodeConversation(conversationId: String, inboxId: String, clientId: String) async {
        Log.info("Exploding conversation \(conversationId) for inbox \(inboxId)")

        do {
            // First, get the messaging service and metadata writer
            let messagingService = messagingService(for: clientId, inboxId: inboxId)
            let metadataWriter = messagingService.conversationMetadataWriter()

            // Fetch the conversation to get member IDs
            let conversation = try await databaseReader.read { db in
                try DBConversation.fetchOne(db, id: conversationId)
            }

            if let conversation {
                // Get all member IDs (we'll try to remove everyone)
                let allMemberIds = try await databaseReader.read { db in
                    try DBConversationMember
                        .filter(DBConversationMember.Columns.conversationId == conversationId)
                        .filter(DBConversationMember.Columns.inboxId != inboxId) // Exclude current user
                        .fetchAll(db)
                        .map { $0.inboxId }
                }

                // Set the expiration to now
                Log.info("Setting expiration to now for conversation \(conversationId)")
                try await metadataWriter.updateExpiresAt(Date(), for: conversationId)

                // Remove all other members
                if !allMemberIds.isEmpty {
                    Log.info("Removing \(allMemberIds.count) members from conversation \(conversationId)")
                    try await metadataWriter.removeMembers(allMemberIds, from: conversationId)
                }
            } else {
                Log.warning("Conversation \(conversationId) not found, will just delete inbox")
            }

            // Cancel any scheduled explode notifications for this conversation
            // (do this before deleting inbox in case of failure)
            ExplodeNotificationManager.cancelExplodeNotification(for: conversationId)

            // Delete the inbox (which includes the conversation)
            try await deleteInbox(clientId: clientId)

            // Then, post notification for UI update after all operations complete
            NotificationCenter.default.post(
                name: .leftConversationNotification,
                object: nil,
                userInfo: [
                    "clientId": clientId,
                    "inboxId": inboxId,
                    "conversationId": conversationId
                ]
            )

            Log.info("Successfully exploded conversation \(conversationId)")
        } catch {
            Log.error("Failed to explode conversation: \(error.localizedDescription)")

            // Still post notification on error to update UI
            NotificationCenter.default.post(
                name: .leftConversationNotification,
                object: nil,
                userInfo: [
                    "clientId": clientId,
                    "inboxId": inboxId,
                    "conversationId": conversationId,
                    "error": error.localizedDescription
                ]
            )
        }
    }

    // MARK: - Inbox Management

    public func addInbox() async -> AnyMessagingService {
        let messagingService = await unusedInboxCache.consumeOrCreateMessagingService(
            databaseWriter: databaseWriter,
            databaseReader: databaseReader,
            environment: environment
        )
        serviceQueue.sync {
            let clientId = messagingService.clientId
            messagingServices[clientId] = messagingService
        }
        return messagingService
    }

    public func deleteInbox(clientId: String) async throws {
        let service: AnyMessagingService? = serviceQueue.sync {
            messagingServices.removeValue(forKey: clientId)
        }

        guard let service = service else {
            Log.error("Messaging service not found for clientId \(clientId)")
            throw SessionManagerError.inboxNotFound
        }

        Log.info("Stopping messaging service for clientId: \(clientId)")
        await service.stopAndDelete()

        // Delete from database
        let inboxWriter = InboxWriter(dbWriter: databaseWriter)
        try await inboxWriter.delete(clientId: clientId)
    }

    public func deleteAllInboxes() async throws {
        // Always clear device registration state, even if deletion fails
        defer { DeviceRegistrationManager.clearRegistrationState() }

        let services = serviceQueue.sync(flags: .barrier) {
            let copy = Array(messagingServices.values)
            messagingServices.removeAll()
            return copy
        }

        await withTaskGroup(of: Void.self) { group in
            for messagingService in services {
                group.addTask {
                    await messagingService.stopAndDelete()
                }
            }
        }

        // Delete all from database
        let inboxWriter = InboxWriter(dbWriter: databaseWriter)
        Log.info("Deleting all inboxes from database")
        try await inboxWriter.deleteAll()
    }

    // MARK: - Messaging Services

    public func messagingService(for clientId: String, inboxId: String) -> AnyMessagingService {
        serviceQueue.sync {
            if let existingService = messagingServices[clientId] {
                return existingService
            }
            let newService = startMessagingService(for: inboxId, clientId: clientId)
            messagingServices[clientId] = newService
            return newService
        }
    }

    // MARK: - Factory methods for repositories

    public func inviteRepository(for conversationId: String) -> any InviteRepositoryProtocol {
        InviteRepository(
            databaseReader: databaseReader,
            conversationId: conversationId,
            conversationIdPublisher: Just(conversationId).eraseToAnyPublisher()
        )
    }

    public func conversationRepository(for conversationId: String, inboxId: String, clientId: String) -> any ConversationRepositoryProtocol {
        let messagingService = messagingService(for: clientId, inboxId: inboxId)
        return ConversationRepository(
            conversationId: conversationId,
            dbReader: databaseReader,
            inboxStateManager: messagingService.inboxStateManager
        )
    }

    public func messagesRepository(for conversationId: String) -> any MessagesRepositoryProtocol {
        MessagesRepository(
            dbReader: databaseReader,
            conversationId: conversationId
        )
    }

    public func conversationsRepository(for consent: [Consent]) -> any ConversationsRepositoryProtocol {
        ConversationsRepository(dbReader: databaseReader, consent: consent)
    }

    public func conversationsCountRepo(for consent: [Consent], kinds: [ConversationKind]) -> any ConversationsCountRepositoryProtocol {
        ConversationsCountRepository(databaseReader: databaseReader, consent: consent, kinds: kinds)
    }

    // MARK: Notification Display Logic

    public func shouldDisplayNotification(for conversationId: String) async -> Bool {
        let currentActiveConversationId = serviceQueue.sync { activeConversationId }

        // Don't display notification if we're in the conversations list
        guard let currentActiveConversationId else {
            Log.info("Suppressing notification from conversations list: \(conversationId)")
            return false
        }

        // Don't display notification if it's for the currently active conversation
        if currentActiveConversationId == conversationId {
            Log.info("Suppressing notification for active conversation: \(conversationId)")
            return false
        }
        return true
    }

    public func inboxId(for conversationId: String) async -> String? {
        do {
            return try await databaseReader.read { db in
                try DBConversation
                    .filter(DBConversation.Columns.id == conversationId)
                    .fetchOne(db)?
                    .inboxId
            }
        } catch {
            Log.error("Failed to look up inboxId for conversationId \(conversationId): \(error)")
            return nil
        }
    }
}
