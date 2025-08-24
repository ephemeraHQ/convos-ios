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
    private var cancellables: Set<AnyCancellable> = []
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
        inboxesRepository.inboxesPublisher
            .sink { [weak self] inboxes in
                do {
                    try self?.startMessagingServices(for: inboxes)
                } catch {
                    Logger.error("Error starting messaging services: \(error.localizedDescription)")
                }
            }
            .store(in: &cancellables)
        observe()
    }

    deinit {
        if let leftConversationObserver {
            NotificationCenter.default.removeObserver(leftConversationObserver)
        }
        cancellables.removeAll()
        messagingServices.removeAll()
    }

    // MARK: - Private Methods

    private func startMessagingServices(for inboxes: [Inbox]) throws {
        let inboxIds = Set(inboxes.map(\.inboxId))
        let existingInboxIds = Set(messagingServices.map { $0.identifier })
        let newInboxIds = inboxIds.subtracting(existingInboxIds)
        let oldInboxIds = existingInboxIds.subtracting(inboxIds)
        Logger
            .info(
                "Starting messaging services: \(newInboxIds), stopping for: \(oldInboxIds). Current count: \(messagingServices.count)"
            )
        for inboxId in newInboxIds {
            _ = startMessagingService(for: inboxId)
        }
        for oldInboxId in oldInboxIds {
            try deleteInbox(inboxId: oldInboxId)
        }
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

    func addInbox() throws -> AnyMessagingService {
        let messagingService = MessagingService.registeredMessagingService(
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
        messagingServices.forEach { $0.stopAndDelete() }
        messagingServices.removeAll()

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
