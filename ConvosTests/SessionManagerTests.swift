@testable import Convos
import Testing
import Combine

struct SessionManagerTests {
    @Test("Authorizing starts messaging service")
    func testAuthStartsMessaging() async throws {
        let authService = MockAuthService()
        let databaseWriter = MockDatabaseManager.shared.dbWriter
        let databaseReader = MockDatabaseManager.shared.dbReader
        let sessionManager = SessionManager(
            authService: authService,
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

        guard let firstInboxes = await inboxesIterator.next(),
              let inbox = firstInboxes.first else {
            Issue.record("Inbox not found")
            return
        }

        let inboxId = inbox.inboxId
        Logger.info("🔍 Found inbox with ID: \(inboxId)")

        let messagingService = sessionManager.messagingService(for: inboxId)
        var inboxReadyIterator = messagingService.inboxReadyPublisher.values.makeAsyncIterator()

        Logger.info("🔍 Waiting for messaging service...")
        guard let inboxReady = await inboxReadyIterator.next() else {
            Issue.record("Messaging service not published")
            return
        }

        Logger.info("🔍 Got messaging service with inboxId: \(inboxReady.client.inboxId)")
        #expect(inboxReady.client.inboxId == inboxId)
    }
}
