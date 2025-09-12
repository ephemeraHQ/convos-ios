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

actor SessionManager: SessionManagerProtocol {
    private var leftConversationObserver: Any?
    private var activeConversationObserver: Any?
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
        if let activeConversationObserver {
            NotificationCenter.default.removeObserver(activeConversationObserver)
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

        activeConversationObserver = NotificationCenter.default
            .addObserver(forName: .activeConversationChanged, object: nil, queue: .main) { notification in
                Task { [weak self] in
                    guard let self else { return }
                    let conversationId = notification.userInfo?["conversationId"] as? String
                    await self.setActiveConversationId(conversationId)
                    Logger.info("Active conversation changed to: \(conversationId ?? "none")")
                }
            }
    }

    private func setActiveConversationId(_ conversationId: String?) {
        activeConversationId = conversationId
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

    // MARK: - Inbox Management

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
    }

    // MARK: - Messaging Services

    func messagingService(for inboxId: String) async -> AnyMessagingService {
        if let existingService = messagingServices.first(where: { $0.identifier == inboxId }) {
            Logger.info("Existing messaging service found")
            return existingService
        }

        Logger.info("Messaging service not found, starting...")
        return startMessagingService(for: inboxId)
    }

    // MARK: - Factory methods for repositories

    nonisolated func inviteRepository(for conversationId: String) -> any InviteRepositoryProtocol {
        InviteRepository(
            databaseReader: databaseReader,
            conversationId: conversationId,
            conversationIdPublisher: Just(conversationId).eraseToAnyPublisher()
        )
    }

    nonisolated func conversationRepository(for conversationId: String) -> any ConversationRepositoryProtocol {
        ConversationRepository(
            conversationId: conversationId,
            dbReader: databaseReader
        )
    }

    nonisolated func messagesRepository(for conversationId: String) -> any MessagesRepositoryProtocol {
        MessagesRepository(
            dbReader: databaseReader,
            conversationId: conversationId
        )
    }

    nonisolated func conversationsRepository(for consent: [Consent]) -> any ConversationsRepositoryProtocol {
        ConversationsRepository(dbReader: databaseReader, consent: consent)
    }

    nonisolated func conversationsCountRepo(for consent: [Consent], kinds: [ConversationKind]) -> any ConversationsCountRepositoryProtocol {
        ConversationsCountRepository(databaseReader: databaseReader, consent: consent, kinds: kinds)
    }

    // MARK: Notification Display Logic

    func shouldDisplayNotification(for conversationId: String) async -> Bool {
        // Don't display notification if we're in the conversations list
        guard let activeConversationId else {
            Logger.info("Suppressing notification from conversations list: \(conversationId)")
            return false
        }

        // Don't display notification if it's for the currently active conversation
        if activeConversationId == conversationId {
            Logger.info("Suppressing notification for active conversation: \(conversationId)")
            return false
        }
        return true
    }
}
