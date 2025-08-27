import Combine
import Foundation
import GRDB
import UserNotifications
import Security

public extension Notification.Name {
    static let leftConversationNotification: Notification.Name = Notification.Name("LeftConversationNotification")
}

public typealias AnyMessagingService = any MessagingServiceProtocol
public typealias AnyClientProvider = any XMTPClientProvider

enum SessionManagerError: Error {
    case inboxNotFound
}

actor SessionManager: SessionManagerProtocol {
    private var leftConversationObserver: Any?
    private var messagingServices: [AnyMessagingService] = []

    private let databaseWriter: any DatabaseWriter
    private let databaseReader: any DatabaseReader
    private let environment: AppEnvironment

    init(databaseWriter: any DatabaseWriter,
         databaseReader: any DatabaseReader,
         environment: AppEnvironment) {
        self.databaseWriter = databaseWriter
        self.databaseReader = databaseReader
        self.environment = environment
        self.messagingServices = []

        let inboxesRepository = InboxesRepository(databaseReader: databaseReader)
        Task { [weak self] in
            guard let self else { return }
            do {
                let inboxes = try inboxesRepository.allInboxes()
                try await self.startMessagingServices(for: inboxes)
            } catch {
                Logger.error("Error starting messaging services: \(error.localizedDescription)")
            }
        }

        Task { await observe() }

        // Schedule creation of unused inbox on app startup
        MessagingService.createUnusedInboxIfNeeded(
            databaseWriter: databaseWriter,
            databaseReader: databaseReader,
            environment: environment
        )
    }

    deinit {
        if let leftConversationObserver {
            NotificationCenter.default.removeObserver(leftConversationObserver)
        }
        messagingServices.removeAll()
    }

    // MARK: - Private Methods

    private func startMessagingServices(for inboxes: [Inbox]) throws {
        let inboxIds = inboxes.map { $0.inboxId }
        Logger.info("Starting messaging services for inboxes: \(inboxIds)")
        for inboxId in inboxIds {
            _ = startMessagingService(for: inboxId)
        }
    }

    private func startMessagingService(for inboxId: String) -> AnyMessagingService {
        let messagingService = MessagingService.authorizedMessagingService(
            for: inboxId,
            databaseWriter: databaseWriter,
            databaseReader: databaseReader,
            environment: environment,
            startsStreamingServices: true
        )
        messagingServices.append(messagingService)
        return messagingService
    }

    private func observe() {
        leftConversationObserver = NotificationCenter.default
            .addObserver(forName: .leftConversationNotification, object: nil, queue: .main) { notification in
                Task { [weak self] in
                    guard let self else { return }
                    guard let inboxId: String = notification.userInfo?["inboxId"] as? String else {
                        return
                    }

                    // Schedule explosion notification if conversationId is provided
                    if let conversationId: String = notification.userInfo?["conversationId"] as? String {
                        await self.scheduleExplosionNotification(inboxId: inboxId, conversationId: conversationId)
                    }

                    do {
                        try await self.deleteInbox(inboxId: inboxId)
                    } catch {
                        Logger.error("Error deleting account from left conversation notification: \(error.localizedDescription)")
                    }
                }
            }
    }

    // MARK: - Local Notification

    private func scheduleExplosionNotification(inboxId: String, conversationId: String) async {
        do {
            let conversation = try await fetchConversationDetails(conversationId: conversationId)

            let content = UNMutableNotificationContent()
            content.title = "💥 \(conversation.displayName) 💥"
            content.body = "A convo exploded"
            content.sound = .default
            content.userInfo = [
                "inboxId": inboxId,
                "conversationId": conversationId,
                "notificationType": "explosion"
            ]

            if let cachedImage = ImageCache.shared.image(for: conversation),
               let cachedImageData = cachedImage.jpegData(compressionQuality: 1.0) {
                do {
                    let tempDirectory = FileManager.default.temporaryDirectory
                    let tempFileName = "explosion-\(conversationId)-\(UUID().uuidString).jpg"
                    let tempFileURL = tempDirectory.appendingPathComponent(tempFileName)
                    try cachedImageData.write(to: tempFileURL)

                    // Create notification attachment
                    let attachment = try UNNotificationAttachment(
                        identifier: UUID().uuidString,
                        url: tempFileURL,
                        options: nil
                    )
                    content.attachments = [attachment]

                    Logger.info("Successfully added conversation image to explosion notification")
                } catch {
                    Logger.warning("Failed to download or create notification attachment: \(error)")
                }
            }

            let request = UNNotificationRequest(
                identifier: "explosion-\(conversationId)",
                content: content,
                trigger: nil // Immediate trigger
            )
            try await UNUserNotificationCenter.current().add(request)
            Logger.info("Scheduled explosion notification for conversation: \(conversationId)")
        } catch {
            Logger.error("Failed to schedule explosion notification: \(error)")
        }
    }

    private func fetchConversationDetails(conversationId: String) async throws -> Conversation {
        return try await withCheckedThrowingContinuation { continuation in
            let conversationRepository = ConversationRepository(
                conversationId: conversationId,
                dbReader: databaseReader
            )

            do {
                if let conversation = try conversationRepository.fetchConversation() {
                    continuation.resume(returning: conversation)
                } else {
                    continuation.resume(throwing: ConversationRepositoryError.failedFetchingConversation)
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: Public

    func addInbox() async throws -> AnyMessagingService {
        let messagingService = await MessagingService.registeredMessagingService(
            databaseWriter: databaseWriter,
            databaseReader: databaseReader,
            environment: environment
        )
        messagingServices.append(messagingService)
        return messagingService
    }

    func deleteInbox(for messagingService: AnyMessagingService) async throws {
        guard let messagingServiceIndex = messagingServices.firstIndex(
            where: { $0.identifier == messagingService.identifier || $0 === messagingService }
        ) else {
            Logger.error("Inbox to delete for messaging service not found")
            return
        }
        let service = messagingServices[messagingServiceIndex]
        Logger.info("Stopping messaging service with id: \(service.identifier)")
        await service.stopAndDelete()
        messagingServices.remove(at: messagingServiceIndex)
    }

    func deleteInbox(inboxId: String) async throws {
        guard let messagingServiceIndex = messagingServices.firstIndex(where: { $0.identifier == inboxId }) else {
            Logger.error("Inbox to delete for inbox id \(inboxId) not found")
            return
        }
        let messagingService = messagingServices[messagingServiceIndex]
        Logger.info("Stopping messaging service with id: \(messagingService.identifier)")
        await messagingService.stopAndDelete()
        messagingServices.remove(at: messagingServiceIndex)
    }

    func deleteAllInboxes() async throws {
        let services = messagingServices // Get a local copy
        await withTaskGroup(of: Void.self) { group in
            for messagingService in services {
                group.addTask {
                    await messagingService.stopAndDelete()
                }
            }
        }
        messagingServices.removeAll()

        // After all inboxes are deleted, wipe shared state that may recreate or re-authenticate
        await UnusedInboxCache.shared.reset()

        // Clear any APNS token stored in UserDefaults
        PushNotificationRegistrar.clearToken()

        // Clear shared environment config stored for the NSE
        AppEnvironment.clearSecureConfigurationForNotificationExtension()

        // Clear any JWTs/push tokens that aren't tied to a specific inbox anymore (best-effort sweep)
        // JWTs and push tokens are keyed by inboxId; since we've deleted all inboxes, try to delete all matching items.
        // Use the keychain access group configured for this environment so we cover app + extension.
        do {
            try await environment.defaultIdentityStore.deleteAll()
        } catch {
            // Ignore errors; identities for deleted inboxes may already be gone
        }

        // Best-effort: remove all generic-password items for our shared service (JWTs, push tokens)
        let keychainSweepQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "org.convos.ios"
        ]
        SecItemDelete(keychainSweepQuery as CFDictionary)

        // Remove App Group databases and XMTP stores
        let fileManager = FileManager.default
        let groupURL = environment.defaultDatabasesDirectoryURL
        do {
            let contents = try fileManager.contentsOfDirectory(at: groupURL, includingPropertiesForKeys: nil)

            let namesToDelete: Set<String> = [
                "convos.sqlite",
                "convos.sqlite-wal",
                "convos.sqlite-shm"
            ]

            for url in contents {
                let name = url.lastPathComponent
                if namesToDelete.contains(name) {
                    try? fileManager.removeItem(at: url)
                    continue
                }
                if name.hasPrefix("xmtp-") || name.hasPrefix("xmtp_localhost-") {
                    try? fileManager.removeItem(at: url)
                }
            }

            // Remove logs directory content
            let logsDir = groupURL.appendingPathComponent("Logs")
            if let logContents = try? fileManager.contentsOfDirectory(at: logsDir, includingPropertiesForKeys: nil) {
                for item in logContents {
                    try? fileManager.removeItem(at: item)
                }
            }
        } catch {
            // Ignore file removal errors; safe best-effort cleanup
        }
    }

    // MARK: Messaging

    func messagingService(for inboxId: String) async -> AnyMessagingService {
        if let existingService = messagingServices.first(where: { $0.identifier == inboxId }) {
            return existingService
        }

        Logger.info("Messaging service not found, starting...")
        return startMessagingService(for: inboxId)
    }

    // MARK: Displaying All Conversations

    nonisolated func conversationsRepository(for consent: [Consent]) -> any ConversationsRepositoryProtocol {
        ConversationsRepository(dbReader: databaseReader, consent: consent)
    }

    nonisolated func conversationsCountRepo(for consent: [Consent], kinds: [ConversationKind]) -> any ConversationsCountRepositoryProtocol {
        ConversationsCountRepository(databaseReader: databaseReader, consent: consent, kinds: kinds)
    }
}
