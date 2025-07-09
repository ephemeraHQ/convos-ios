@testable import Convos
import Testing
import Combine

struct SessionManagerTests {
    @Test("Authorizing starts messaging service")
    func testAuthStartsMessaging() async throws {
        let authService = MockAuthService()
        let localAuthService = SecureEnclaveAuthService()
        let databaseWriter = MockDatabaseManager.shared.dbWriter
        let databaseReader = MockDatabaseManager.shared.dbReader
        let sessionManager = SessionManager(
            authService: authService,
            localAuthService: localAuthService,
            databaseWriter: databaseWriter,
            databaseReader: databaseReader,
            environment: .tests
        )

        let inboxesPublisher = sessionManager.inboxesRepository.inboxesPublisher
        var inboxesIterator = inboxesPublisher
            .filter { !$0.isEmpty }
            .values
            .makeAsyncIterator()

        Logger.info("🔍 Registering user...")
        try await authService.register(displayName: "Name")
        Logger.info("🔍 Registration completed")

        let firstInboxes = await withTimeout(seconds: 10) {
            await inboxesIterator.next()
        }
        #expect(firstInboxes != nil, "Inbox not found")

        let inbox = firstInboxes!.first!
        let inboxId = inbox.inboxId
        Logger.info("🔍 Found inbox with ID: \(inboxId)")

        let messagingService = sessionManager.messagingService(for: inboxId)
        var inboxReadyIterator = messagingService.inboxReadyPublisher.values.makeAsyncIterator()

        Logger.info("🔍 Waiting for messaging service...")
        let inboxReady = await withTimeout(seconds: 10) {
            await inboxReadyIterator.next()
        }
        #expect(inboxReady != nil, "Messaging service not published")

        Logger.info("🔍 Got messaging service with inboxId: \(inboxReady!.client.inboxId)")
        #expect(inboxReady!.client.inboxId == inboxId)
    }

    @Test("Test local auth starts messaging service")
    func testLocalAuthStartsMessaging() async throws {
        let authService = MockAuthService()
        let localAuthService = SecureEnclaveAuthService()
        let databaseWriter = MockDatabaseManager.shared.dbWriter
        let databaseReader = MockDatabaseManager.shared.dbReader
        let sessionManager = SessionManager(
            authService: authService,
            localAuthService: localAuthService,
            databaseWriter: databaseWriter,
            databaseReader: databaseReader,
            environment: .tests
        )

        let inboxesPublisher = sessionManager.inboxesRepository.inboxesPublisher
        var inboxesIterator = inboxesPublisher
            .filter { !$0.isEmpty }
            .values
            .makeAsyncIterator()

        Logger.info("🔍 Registering local user...")
        _ = try localAuthService.register(displayName: "User", inboxType: .standard)
        Logger.info("🔍 Registration completed")

        let firstInboxes = await withTimeout(seconds: 10) {
            await inboxesIterator.next()
        }
        #expect(firstInboxes != nil, "Inbox not found")
        #expect(!firstInboxes!.isEmpty, "No inboxes found")

        let inbox = firstInboxes!.first!
        let inboxId = inbox.inboxId
        Logger.info("🔍 Found inbox with ID: \(inboxId)")

        let messagingService = sessionManager.messagingService(for: inboxId)
        var inboxReadyIterator = messagingService.inboxReadyPublisher.values.makeAsyncIterator()

        Logger.info("🔍 Waiting for messaging service...")
        let inboxReady = await withTimeout(seconds: 10) {
            await inboxReadyIterator.next()
        }
        #expect(inboxReady != nil, "Messaging service not published")

        Logger.info("🔍 Got messaging service with inboxId: \(inboxReady!.client.inboxId)")
        #expect(inboxReady!.client.inboxId == inboxId)
    }

}
