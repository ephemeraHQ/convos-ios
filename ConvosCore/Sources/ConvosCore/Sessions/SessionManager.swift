import Combine
import Foundation
import GRDB
import UserNotifications

public extension Notification.Name {
    static let leftConversationNotification: Notification.Name = Notification.Name("LeftConversationNotification")
}

public typealias AnyMessagingService = any MessagingServiceProtocol
public typealias AnyClientProvider = any XMTPClientProvider

enum SessionManagerError: Error {
    case inboxNotFound
}

class SessionManager: SessionManagerProtocol {
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
        Task { [weak self, inboxesRepository] in
            guard let self else { return }
            do {
                let inboxes = try inboxesRepository.allInboxes()
                try startMessagingServices(for: inboxes)
            } catch {
                Logger.error("Error starting messaging services: \(error.localizedDescription)")
            }
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
        messagingServices.removeAll()
    }

    // MARK: - Private Methods

    private func startMessagingServices(for inboxes: [Inbox]) throws {
        let inboxIds = inboxes.map { $0.inboxId }
        Logger.info("Starting messaging services for inboxes: \(inboxIds)")
        inboxIds.forEach { _ = startMessagingService(for: $0) }
    }

    private func startMessagingService(for inboxId: String) -> AnyMessagingService {
        let messagingService = MessagingService.authorizedMessagingService(
            for: inboxId,
            databaseWriter: databaseWriter,
            databaseReader: databaseReader,
            environment: environment
        )
        messagingServices.append(messagingService)
        return messagingService
    }

    private func observe() {
        leftConversationObserver = NotificationCenter.default
            .addObserver(forName: .leftConversationNotification, object: nil, queue: .main) { [weak self] notification in
                guard let self else { return }
                guard let inboxId: String = notification.userInfo?["inboxId"] as? String else {
                    return
                }

                // Schedule explosion notification if conversationId is provided
                if let conversationId: String = notification.userInfo?["conversationId"] as? String {
                    Task {
                        await self.scheduleExplosionNotification(inboxId: inboxId, conversationId: conversationId)
                    }
                }

                do {
                    try deleteInbox(inboxId: inboxId)
                } catch {
                    Logger
                        .error(
                            "Error deleting account from left conversation notification: \(error.localizedDescription)"
                        )
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

    func deleteInbox(for messagingService: AnyMessagingService) throws {
        guard let messagingServiceIndex = messagingServices.firstIndex(
            where: { $0.identifier == messagingService.identifier || $0 === messagingService }
        ) else {
            Logger.error("Inbox to delete for messaging service not found")
            return
        }
        let messagingService = messagingServices[messagingServiceIndex]
        Logger.info("Stopping messaging service with id: \(messagingService.identifier)")
        messagingService.stopAndDelete()
    }

    func deleteInbox(inboxId: String) throws {
        guard let messagingServiceIndex = messagingServices.firstIndex(where: { $0.identifier == inboxId }) else {
            Logger.error("Inbox to delete for inbox id \(inboxId) not found")
            return
        }
        let messagingService = messagingServices[messagingServiceIndex]
        messagingService.stopAndDelete()
        messagingServices.remove(at: messagingServiceIndex)
    }

    func deleteAllInboxes() throws {
        Task { [weak self] in
            guard let self else { return }
            await withTaskGroup { group in
                for messagingService in self.messagingServices {
                    group.addTask {
                        await messagingService.stopAndDelete()
                    }
                }
            }
            self.messagingServices.removeAll()
        }
    }

    // MARK: Messaging

    func messagingService(for inboxId: String) -> AnyMessagingService {
        guard let messagingService = messagingServices.first(where: { $0.identifier == inboxId }) else {
            Logger.info("Messaging service not found, starting...")
            return startMessagingService(for: inboxId)
        }

        return messagingService
    }

    // MARK: Displaying All Conversations

    func conversationsRepository(for consent: [Consent]) -> any ConversationsRepositoryProtocol {
        ConversationsRepository(dbReader: databaseReader, consent: consent)
    }

    func conversationsCountRepo(for consent: [Consent], kinds: [ConversationKind]) -> any ConversationsCountRepositoryProtocol {
        ConversationsCountRepository(databaseReader: databaseReader, consent: consent, kinds: kinds)
    }
}
