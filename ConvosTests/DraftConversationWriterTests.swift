@testable import Convos
import Foundation
import Testing

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

        guard let firstInboxes = await inboxesIterator.next(),
              let inbox = firstInboxes.first else {
            Issue.record("Inbox not found")
            return ""
        }

        let inboxId = inbox.inboxId
        Logger.info("🔍 Found inbox with ID: \(inboxId)")

        return inboxId
    }

    @Test("Adding a member creates a draft conversation")
    func testAddingMemberCreatesDraftConversation() async throws {
        let client = try await clientHolder.get()
        let inboxesPublisher = client.session.inboxesRepository.inboxesPublisher
        var inboxesIterator = inboxesPublisher
            .filter { !$0.isEmpty }
            .values
            .makeAsyncIterator()
        guard let firstInboxes = await inboxesIterator.next(),
              let inbox = firstInboxes.first else {
            Issue.record("Inbox not found")
            return
        }
        let inboxId = inbox.inboxId
        let messagingService = client.session.messagingService(for: inboxId)
        var inboxReadyIterator = messagingService.inboxReadyPublisher.values.makeAsyncIterator()
        guard let _ = await inboxReadyIterator.next() else {
            Issue.record("Messaging service not published")
            return
        }

        let composer = messagingService.draftConversationComposer()
        let writer = composer.draftConversationWriter
        let repository = composer.draftConversationRepository
        let firstProfile = MemberProfile(inboxId: UUID().uuidString, name: "A", username: "a", avatar: nil)
        Task {
            try await writer.add(profile: firstProfile)
        }
        _ = try await repository.conversationPublisher
            .waitForFirstMatch(where: { $0?.members == [firstProfile.hydrateProfile()] })
        Task {
            try await writer.remove(profile: firstProfile)
        }
        _ = try await repository.conversationPublisher
            .waitForFirstMatch(where: { $0?.members.isEmpty ?? true })
    }

    @Test("Removing a member changes conversation kind (dm or group)")
    func testRemovingMemberChangesConversationKind() async throws {
        let client = try await clientHolder.get()
        let inboxesPublisher = client.session.inboxesRepository.inboxesPublisher
        var inboxesIterator = inboxesPublisher
            .filter { !$0.isEmpty }
            .values
            .makeAsyncIterator()
        guard let firstInboxes = await inboxesIterator.next(),
              let inbox = firstInboxes.first else {
            Issue.record("Inbox not found")
            return
        }
        let inboxId = inbox.inboxId
        let messagingService = client.session.messagingService(for: inboxId)
        var inboxReadyIterator = messagingService.inboxReadyPublisher.values.makeAsyncIterator()
        guard let _ = await inboxReadyIterator.next() else {
            Issue.record("Messaging service not published")
            return
        }
        let composer = messagingService.draftConversationComposer()
        let writer = composer.draftConversationWriter
        let repository = composer.draftConversationRepository
        let firstProfile = MemberProfile(inboxId: UUID().uuidString, name: "A", username: "a", avatar: nil)
        var conversationIterator = repository.conversationPublisher.values.makeAsyncIterator()
        try await writer.add(profile: firstProfile)
        let conversation1 = await conversationIterator.next()
        #expect(conversation1??.kind == .dm)
        let secondProfile = MemberProfile(inboxId: UUID().uuidString, name: "B", username: "b", avatar: nil)
        try await writer.add(profile: secondProfile)
        let conversation2 = await conversationIterator.next()
        #expect(conversation2??.kind == .group)
        try await writer.remove(profile: firstProfile)
        let conversation3 = await conversationIterator.next()
        #expect(conversation3??.kind == .dm)
    }

    @Test("Sending a message creates the conversation on XMTP")
    func testSendingMessageCreatesConversation() async throws {
        let client = try await clientHolder.get()
        let inboxesPublisher = client.session.inboxesRepository.inboxesPublisher
        var inboxesIterator = inboxesPublisher
            .filter { !$0.isEmpty }
            .values
            .makeAsyncIterator()
        guard let firstInboxes = await inboxesIterator.next(),
              let inbox = firstInboxes.first else {
            Issue.record("Inbox not found")
            return
        }
        let inboxId = inbox.inboxId
        let messagingService = client.session.messagingService(for: inboxId)
        var inboxReadyIterator = messagingService.inboxReadyPublisher.values.makeAsyncIterator()
        guard let _ = await inboxReadyIterator.next() else {
            Issue.record("Messaging service not published")
            return
        }
        let composer = messagingService.draftConversationComposer()
        let writer = composer.draftConversationWriter
        let repository = composer.draftConversationRepository

        let otherInboxId = try await registerTemporaryInboxId()
        let firstProfile = MemberProfile(inboxId: otherInboxId, name: "A", username: "a", avatar: nil)
        Task {
            try await writer.add(profile: firstProfile)
        }
        _ = try await repository.conversationPublisher
            .waitForFirstMatch(where: { $0?.kind == .dm })
        Task {
            try await writer.send(text: "GM!")
        }
        let messages = try await repository
            .messagesRepository
            .messagesPublisher
            .waitForFirstMatch(where: { $0.count == 1 })
        #expect(messages.count == 1)
        let secondMessages = try await repository
            .messagesRepository
            .messagesPublisher
            .waitForFirstMatch(where: { $0.count == 2})
        #expect(secondMessages.count == 2)
        #expect(secondMessages.last?.base.content == .text("GM!"))
    }

    @Test("Adding members that have an existing conversation")
    func testAddingMembersWithExistingConversation() async throws {
        let client = try await clientHolder.get()
        let inboxesPublisher = client.session.inboxesRepository.inboxesPublisher
        var inboxesIterator = inboxesPublisher
            .filter { !$0.isEmpty }
            .values
            .makeAsyncIterator()
        guard let firstInboxes = await inboxesIterator.next(),
              let inbox = firstInboxes.first else {
            Issue.record("Inbox not found")
            return
        }
        let inboxId = inbox.inboxId
        let messagingService = client.session.messagingService(for: inboxId)
        var inboxReadyIterator = messagingService.inboxReadyPublisher.values.makeAsyncIterator()
        guard let _ = await inboxReadyIterator.next() else {
            Issue.record("Messaging service not published")
            return
        }
        let composer = messagingService.draftConversationComposer()
        let writer = composer.draftConversationWriter
        let repository = composer.draftConversationRepository
        var conversationIterator = repository.conversationPublisher.values.makeAsyncIterator()
        var messagesIterator = repository.messagesRepository.messagesPublisher.values.makeAsyncIterator()
        
        let otherInboxId = try await registerTemporaryInboxId()
        let firstProfile = MemberProfile(inboxId: otherInboxId, name: "A", username: "a", avatar: nil)
        try await writer.add(profile: firstProfile)
        let conversation1 = await conversationIterator.next()
        #expect(conversation1??.kind == .dm)
        let messages0 = await messagesIterator.next()
        #expect(messages0?.count == 0)
        try await writer.send(text: "GM!")

        let messages1 = await messagesIterator.next()
        #expect(messages1?.count == 2)

        guard let existingConversation = try await messagingService
            .conversationsRepository(for: .allowed)
            .conversationsPublisher
            .waitForFirstMatch(where: { $0.first?.members == [firstProfile.hydrateProfile()] })
            .first else {
            fatalError("Failed to find existing conversation")
        }

        let composer2 = messagingService.draftConversationComposer()
        let writer2 = composer2.draftConversationWriter
        let repository2 = composer2.draftConversationRepository
        var conversationIterator2 = repository2.conversationPublisher.values.makeAsyncIterator()
        try await writer2.add(profile: firstProfile)
        let foundConversation = await conversationIterator2.next()
        #expect(foundConversation??.id == existingConversation.id)
        #expect(foundConversation??.members == existingConversation.members)
    }
}
