@testable import Convos
import Foundation
import Testing
import Combine

private actor ClientHolder {
    private var client: ConvosClient?

    func get() async throws -> ConvosClient {
        if let client = self.client {
            return client
        }

        let authService = MockAuthService()
        let client = ConvosClient.testClient(authService: authService)
        try await client.register(displayName: "Name")
        self.client = client
        return client
    }
}

@Suite("DraftConversationWriterTests")
struct DraftConversationWriterTests {
    private let clientHolder = ClientHolder()

    private func registerTemporaryInboxId() async throws -> String {
        Logger.info("🔍 Starting temporary inbox registration...")

        let authService = MockAuthService()
        let client = ConvosClient.testClient(authService: authService)

        Logger.info("🔍 Registering user...")
        try await authService.register(displayName: "Test")
        Logger.info("🔍 Registration completed")

        let sessionManager = client.session
        let inboxesPublisher = sessionManager.inboxesRepository.inboxesPublisher
        var inboxesIterator = inboxesPublisher
            .filter { !$0.isEmpty }
            .values
            .makeAsyncIterator()

        Logger.info("🔍 Waiting for inboxes to be available...")
        let firstInboxes = await withTimeout(seconds: 10) {
            await inboxesIterator.next()
        }

        guard let firstInboxes = firstInboxes,
              let inbox = firstInboxes.first else {
            Logger.error("❌ Inbox not found after timeout")
            Issue.record("Inbox not found")
            return ""
        }

        let inboxId = inbox.inboxId
        Logger.info("🔍 Found inbox with ID: \(inboxId)")

        return inboxId
    }

    @Test("Adding a member creates a draft conversation")
    func testAddingMemberCreatesDraftConversation() async throws {
        Logger.info("🔍 Starting test: Adding a member creates a draft conversation")

        let client = try await clientHolder.get()
        let inboxesPublisher = client.session.inboxesRepository.inboxesPublisher
        var inboxesIterator = inboxesPublisher
            .filter { !$0.isEmpty }
            .values
            .makeAsyncIterator()

        Logger.info("🔍 Waiting for inboxes...")
        let firstInboxes = await withTimeout(seconds: 10) {
            await inboxesIterator.next()
        }

        guard let firstInboxes = firstInboxes,
              let inbox = firstInboxes.first else {
            Logger.error("❌ Inbox not found after timeout")
            Issue.record("Inbox not found")
            return
        }

        let inboxId = inbox.inboxId
        Logger.info("🔍 Using inbox ID: \(inboxId)")

        let messagingService = client.session.messagingService(for: inboxId)
        var inboxReadyIterator = messagingService.inboxReadyPublisher.values.makeAsyncIterator()

        Logger.info("🔍 Waiting for messaging service to be ready (30s timeout)...")
        let readyResult = await withTimeout(seconds: 30) {
            await inboxReadyIterator.next()
        }

        guard let _ = readyResult else {
            Logger.error("❌ Messaging service not ready after 30 second timeout")
            Issue.record("Messaging service not published")
            return
        }

        Logger.info("🔍 Messaging service is ready")

        let composer = messagingService.draftConversationComposer()
        let writer = composer.draftConversationWriter
        let repository = composer.draftConversationRepository
        let firstProfile = MemberProfile(inboxId: UUID().uuidString, name: "A", username: "a", avatar: nil)

        Logger.info("🔍 Adding first profile...")
        Task {
            try await writer.add(profile: firstProfile)
        }

        Logger.info("🔍 Waiting for conversation to be created...")
        let conversation = try await repository.conversationPublisher
            .waitForFirstMatch(where: { $0?.members == [firstProfile.hydrateProfile()] })
        Logger.info("🔍 Conversation created successfully")

        Logger.info("🔍 Removing first profile...")
        Task {
            try await writer.remove(profile: firstProfile)
        }

        Logger.info("🔍 Waiting for conversation to be empty...")
        let emptyConversation = try await repository.conversationPublisher
            .waitForFirstMatch(where: { $0?.members.isEmpty ?? true })
        Logger.info("🔍 Conversation is now empty")

        Logger.info("✅ Test completed successfully")
    }

    @Test("Removing a member changes conversation kind (dm or group)")
    func testRemovingMemberChangesConversationKind() async throws {
        Logger.info("🔍 Starting test: Removing a member changes conversation kind")

        let client = try await clientHolder.get()
        let inboxesPublisher = client.session.inboxesRepository.inboxesPublisher
        var inboxesIterator = inboxesPublisher
            .filter { !$0.isEmpty }
            .values
            .makeAsyncIterator()

        Logger.info("🔍 Waiting for inboxes...")
        let firstInboxes = await withTimeout(seconds: 10) {
            await inboxesIterator.next()
        }

        guard let firstInboxes = firstInboxes,
              let inbox = firstInboxes.first else {
            Logger.error("❌ Inbox not found after timeout")
            Issue.record("Inbox not found")
            return
        }

        let inboxId = inbox.inboxId
        Logger.info("🔍 Using inbox ID: \(inboxId)")


        let messagingService = client.session.messagingService(for: inboxId)
        var inboxReadyIterator = messagingService.inboxReadyPublisher.values.makeAsyncIterator()

        Logger.info("🔍 Waiting for messaging service to be ready (30s timeout)...")
        let readyResult = await withTimeout(seconds: 30) {
            await inboxReadyIterator.next()
        }

        guard let _ = readyResult else {
            Logger.error("❌ Messaging service not ready after 30 second timeout")
            Issue.record("Messaging service not published")
            return
        }

        Logger.info("🔍 Messaging service is ready")

        let composer = messagingService.draftConversationComposer()
        let writer = composer.draftConversationWriter
        let repository = composer.draftConversationRepository
        let firstProfile = MemberProfile(inboxId: UUID().uuidString, name: "A", username: "a", avatar: nil)
        var conversationIterator = repository.conversationPublisher.values.makeAsyncIterator()

        Logger.info("🔍 Adding first profile...")
        try await writer.add(profile: firstProfile)

        Logger.info("🔍 Waiting for first conversation state...")
        let conversation1 = await withTimeout(seconds: 10) {
            await conversationIterator.next()
        }
        Logger.info("🔍 Got first conversation: \(String(describing: conversation1))")
        #expect(conversation1??.kind == .dm)

        let secondProfile = MemberProfile(inboxId: UUID().uuidString, name: "B", username: "b", avatar: nil)
        Logger.info("🔍 Adding second profile...")
        try await writer.add(profile: secondProfile)

        Logger.info("🔍 Waiting for second conversation state...")
        let conversation2 = await withTimeout(seconds: 10) {
            await conversationIterator.next()
        }
        Logger.info("🔍 Got second conversation: \(String(describing: conversation2))")
        #expect(conversation2??.kind == .group)

        Logger.info("🔍 Removing first profile...")
        try await writer.remove(profile: firstProfile)

        Logger.info("🔍 Waiting for third conversation state...")
        let conversation3 = await withTimeout(seconds: 10) {
            await conversationIterator.next()
        }
        Logger.info("🔍 Got third conversation: \(String(describing: conversation3))")
        #expect(conversation3??.kind == .dm)

        Logger.info("✅ Test completed successfully")
    }

    @Test("Sending a message creates the conversation on XMTP")
    func testSendingMessageCreatesConversation() async throws {
        Logger.info("🔍 Starting test: Sending a message creates the conversation on XMTP")

        let client = try await clientHolder.get()
        let inboxesPublisher = client.session.inboxesRepository.inboxesPublisher
        var inboxesIterator = inboxesPublisher
            .filter { !$0.isEmpty }
            .values
            .makeAsyncIterator()

        Logger.info("🔍 Waiting for inboxes...")
        let firstInboxes = await withTimeout(seconds: 10) {
            await inboxesIterator.next()
        }

        guard let firstInboxes = firstInboxes,
              let inbox = firstInboxes.first else {
            Logger.error("❌ Inbox not found after timeout")
            Issue.record("Inbox not found")
            return
        }

        let inboxId = inbox.inboxId
        Logger.info("🔍 Using inbox ID: \(inboxId)")

        let messagingService = client.session.messagingService(for: inboxId)
        var inboxReadyIterator = messagingService.inboxReadyPublisher.values.makeAsyncIterator()

        Logger.info("🔍 Waiting for messaging service to be ready (30s timeout)...")
        let readyResult = await withTimeout(seconds: 30) {
            await inboxReadyIterator.next()
        }

        guard let _ = readyResult else {
            Logger.error("❌ Messaging service not ready after 30 second timeout")
            Issue.record("Messaging service not published")
            return
        }

        Logger.info("🔍 Messaging service is ready")

        let composer = messagingService.draftConversationComposer()
        let writer = composer.draftConversationWriter
        let repository = composer.draftConversationRepository

        let otherInboxId = try await registerTemporaryInboxId()
        Logger.info("🔍 Using other inbox ID: \(otherInboxId)")

        let firstProfile = MemberProfile(inboxId: otherInboxId, name: "A", username: "a", avatar: nil)
        Logger.info("🔍 Adding profile...")
        Task {
            try await writer.add(profile: firstProfile)
        }

        Logger.info("🔍 Waiting for DM conversation...")
        let dmConversation = try await repository.conversationPublisher
            .waitForFirstMatch(where: { $0?.kind == .dm })
        Logger.info("🔍 DM conversation created")

        Logger.info("🔍 Sending message...")
        Task {
            try await writer.send(text: "GM!")
        }

        Logger.info("🔍 Waiting for first message...")
        let messages = try await repository
            .messagesRepository
            .messagesPublisher
            .waitForFirstMatch(where: { $0.count == 1 })
        Logger.info("🔍 Got first message")
        #expect(messages.count == 1)

        Logger.info("🔍 Waiting for second message...")
        let secondMessages = try await repository
            .messagesRepository
            .messagesPublisher
            .waitForFirstMatch(where: { $0.count == 2})
        Logger.info("🔍 Got second message")
        #expect(secondMessages.count == 2)
        #expect(secondMessages.last?.base.content == .text("GM!"))

        Logger.info("✅ Test completed successfully")
    }

    @Test("Adding members that have an existing conversation")
    func testAddingMembersWithExistingConversation() async throws {
        Logger.info("🔍 Starting test: Adding members that have an existing conversation")

        let client = try await clientHolder.get()
        let inboxesPublisher = client.session.inboxesRepository.inboxesPublisher
        var inboxesIterator = inboxesPublisher
            .filter { !$0.isEmpty }
            .values
            .makeAsyncIterator()

        Logger.info("🔍 Waiting for inboxes...")
        let firstInboxes = await withTimeout(seconds: 10) {
            await inboxesIterator.next()
        }

        guard let firstInboxes = firstInboxes,
              let inbox = firstInboxes.first else {
            Logger.error("❌ Inbox not found after timeout")
            Issue.record("Inbox not found")
            return
        }

        let inboxId = inbox.inboxId
        Logger.info("🔍 Using inbox ID: \(inboxId)")

        let messagingService = client.session.messagingService(for: inboxId)
        var inboxReadyIterator = messagingService.inboxReadyPublisher.values.makeAsyncIterator()

        Logger.info("🔍 Waiting for messaging service to be ready (30s timeout)...")
        let readyResult = await withTimeout(seconds: 30) {
            await inboxReadyIterator.next()
        }

        guard let _ = readyResult else {
            Logger.error("❌ Messaging service not ready after 30 second timeout")
            Issue.record("Messaging service not published")
            return
        }

        Logger.info("🔍 Messaging service is ready")

        let composer = messagingService.draftConversationComposer()
        let writer = composer.draftConversationWriter
        let repository = composer.draftConversationRepository
        var conversationIterator = repository.conversationPublisher.values.makeAsyncIterator()
        var messagesIterator = repository.messagesRepository.messagesPublisher.values.makeAsyncIterator()

        let otherInboxId = try await registerTemporaryInboxId()
        Logger.info("🔍 Using other inbox ID: \(otherInboxId)")

        let firstProfile = MemberProfile(inboxId: otherInboxId, name: "A", username: "a", avatar: nil)
        Logger.info("🔍 Adding first profile...")
        try await writer.add(profile: firstProfile)

        Logger.info("🔍 Waiting for first conversation...")
        let conversation1 = await withTimeout(seconds: 10) {
            await conversationIterator.next()
        }
        Logger.info("🔍 Got first conversation: \(String(describing: conversation1))")
        #expect(conversation1??.kind == .dm)

        Logger.info("🔍 Waiting for initial messages...")
        let messages0 = await withTimeout(seconds: 10) {
            await messagesIterator.next()
        }
        Logger.info("🔍 Got initial messages: \(String(describing: messages0))")
        #expect(messages0?.count == 0)

        Logger.info("🔍 Sending message...")
        try await writer.send(text: "GM!")

        Logger.info("🔍 Waiting for messages after send...")
        let messages1 = await withTimeout(seconds: 10) {
            await messagesIterator.next()
        }
        Logger.info("🔍 Got messages after send: \(String(describing: messages1))")
        #expect(messages1?.count == 2)

        Logger.info("🔍 Waiting for existing conversation...")
        guard let existingConversation = try await messagingService
            .conversationsRepository(for: .allowed)
            .conversationsPublisher
            .waitForFirstMatch(where: { $0.first?.members == [firstProfile.hydrateProfile()] })
            .first else {
            Logger.error("❌ Failed to find existing conversation")
            fatalError("Failed to find existing conversation")
        }
        Logger.info("🔍 Found existing conversation: \(existingConversation.id)")

        let composer2 = messagingService.draftConversationComposer()
        let writer2 = composer2.draftConversationWriter
        let repository2 = composer2.draftConversationRepository
        var conversationIterator2 = repository2.conversationPublisher.values.makeAsyncIterator()

        Logger.info("🔍 Adding profile to second composer...")
        try await writer2.add(profile: firstProfile)

        Logger.info("🔍 Waiting for found conversation...")
        let foundConversation = await withTimeout(seconds: 10) {
            await conversationIterator2.next()
        }
        Logger.info("🔍 Got found conversation: \(String(describing: foundConversation))")
        #expect(foundConversation??.id == existingConversation.id)
        #expect(foundConversation??.members == existingConversation.members)

        Logger.info("✅ Test completed successfully")
    }
}
