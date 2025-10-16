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

public final class SessionManager: SessionManagerProtocol {
    private var leftConversationObserver: Any?
    private var activeConversationObserver: Any?

    // Thread-safe access to messaging services
    private let serviceQueue: DispatchQueue = DispatchQueue(label: "com.convos.sessionmanager.services")
    private var messagingServices: [AnyMessagingService] = []
    private var activeConversationId: String?

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
        do {
            let inboxes = try inboxesRepository.allInboxes()
            self.startMessagingServices(for: inboxes)
        } catch {
            Logger.error("Error starting messaging services: \(error.localizedDescription)")
        }

        observe()

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
        if let activeConversationObserver {
            NotificationCenter.default.removeObserver(activeConversationObserver)
        }
        messagingServices.removeAll()
    }

    // MARK: - Private Methods

    private func startMessagingServices(for inboxes: [Inbox]) {
        let inboxIds = inboxes.map { $0.inboxId }
        Logger.info("Starting messaging services for inboxes: \(inboxIds)")
        let services = inboxes.map { startMessagingService(for: $0.inboxId) }
        serviceQueue.sync {
            messagingServices.append(contentsOf: services)
        }
    }

    private func startMessagingService(for inboxId: String) -> AnyMessagingService {
        MessagingService.authorizedMessagingService(
            for: inboxId,
            databaseWriter: databaseWriter,
            databaseReader: databaseReader,
            environment: environment,
            startsStreamingServices: true
        )
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
                        Logger.error("Error deleting inbox from left conversation notification: \(error.localizedDescription)")
                    }
                }
            }

        activeConversationObserver = NotificationCenter.default
            .addObserver(forName: .activeConversationChanged, object: nil, queue: .main) { [weak self] notification in
                guard let self else { return }
                let conversationId = notification.userInfo?["conversationId"] as? String
                self.setActiveConversationId(conversationId)
                Logger.info("Active conversation changed to: \(conversationId ?? "none")")
            }
    }

    private func setActiveConversationId(_ conversationId: String?) {
        serviceQueue.sync {
            activeConversationId = conversationId
        }
    }

    // MARK: - Local Notification

    private func scheduleExplosionNotification(inboxId: String, conversationId: String) async {
        do {
            let conversation = try fetchConversationDetails(
                conversationId: conversationId,
                inboxId: inboxId
            )

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

    private func fetchConversationDetails(conversationId: String, inboxId: String) throws -> Conversation {
        let conversationRepository = conversationRepository(for: conversationId, inboxId: inboxId)
        guard let conversation = try conversationRepository.fetchConversation() else {
            throw ConversationRepositoryError.failedFetchingConversation
        }
        return conversation
    }

    // MARK: - Inbox Management

    public func addInbox() async throws -> AnyMessagingService {
        let messagingService = await MessagingService.registeredMessagingService(
            databaseWriter: databaseWriter,
            databaseReader: databaseReader,
            environment: environment
        )
        serviceQueue.sync {
            messagingServices.append(messagingService)
        }
        return messagingService
    }

    public func deleteInbox(for messagingService: AnyMessagingService) async throws {
        let service: AnyMessagingService? = serviceQueue.sync {
            guard let index = messagingServices.firstIndex(where: { $0 === messagingService }) else {
                return nil
            }
            let service = messagingServices[index]
            messagingServices.remove(at: index)
            return service
        }

        guard let service = service else {
            Logger.error("Inbox to delete for messaging service not found")
            return
        }

        Logger.info("Stopping messaging service for inbox")
        await service.stopAndDelete()
    }

    public func deleteInbox(inboxId: String) async throws {
        let service: AnyMessagingService? = serviceQueue.sync {
            guard let index = messagingServices.firstIndex(where: { $0.matches(inboxId: inboxId) }) else {
                return nil
            }
            let service = messagingServices[index]
            messagingServices.remove(at: index)
            return service
        }

        guard let service = service else {
            Logger.error("Messaging service not found for inbox id \(inboxId)")
            return
        }

        Logger.info("Stopping messaging service for inbox: \(inboxId)")
        await service.stopAndDelete()

        // Delete from database
        let inboxWriter = InboxWriter(dbWriter: databaseWriter)
        try await inboxWriter.delete(inboxId: inboxId)
    }

    public func deleteAllInboxes() async throws {
        // Always clear device registration state, even if deletion fails
        defer { DeviceRegistrationManager.clearRegistrationState() }

        let services = serviceQueue.sync {
            let copy = messagingServices
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
        try await inboxWriter.deleteAll()
    }

    // MARK: - Messaging Services

    public func messagingService(for inboxId: String) -> AnyMessagingService {
        // Check if we already have a messaging service for this inbox
        let existingService = serviceQueue.sync {
            messagingServices.first(where: { $0.matches(inboxId: inboxId) })
        }

        if let existingService = existingService {
            return existingService
        }

        // Start a new messaging service for this inbox
        Logger.info("Starting messaging service for inbox: \(inboxId)")
        let newService = startMessagingService(for: inboxId)

        serviceQueue.sync {
            messagingServices.append(newService)
        }

        return newService
    }

    // MARK: - Factory methods for repositories

    public func inviteRepository(for conversationId: String) -> any InviteRepositoryProtocol {
        InviteRepository(
            databaseReader: databaseReader,
            conversationId: conversationId,
            conversationIdPublisher: Just(conversationId).eraseToAnyPublisher()
        )
    }

    public func conversationRepository(for conversationId: String, inboxId: String) -> any ConversationRepositoryProtocol {
        let messagingService = messagingService(for: inboxId)
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
            Logger.info("Suppressing notification from conversations list: \(conversationId)")
            return false
        }

        // Don't display notification if it's for the currently active conversation
        if currentActiveConversationId == conversationId {
            Logger.info("Suppressing notification for active conversation: \(conversationId)")
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
            Logger.error("Failed to look up inboxId for conversationId \(conversationId): \(error)")
            return nil
        }
    }
}
