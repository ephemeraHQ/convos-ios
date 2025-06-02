@testable import Convos
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
        let userRepo = client.messaging.userRepository()
        try await client.register(displayName: "Test")
        _ = try await client.messaging
            .messagingStatePublisher()
            .waitForFirstMatch { $0 == .ready }
        guard let user = try await userRepo.getCurrentUser() else {
            fatalError("Error creating temp inbox id")
        }
        return user.inboxId
    }

    @Test("Adding a member creates a draft conversation")
    func testAddingMemberCreatesDraftConversation() async throws {
        let client = try await clientHolder.get()
        let messaging = client.messaging
        let state = try await messaging
            .messagingStatePublisher()
            .waitForFirstMatch { $0 == .ready }
        #expect(state == .ready)
        let composer = messaging.draftConversationComposer()
        let writer = composer.draftConversationWriter
        let repository = composer.draftConversationRepository
        var conversationIterator = repository.conversationPublisher
            .values
            .makeAsyncIterator()
        _ = await conversationIterator.next() // ignore first
        let firstProfile = MemberProfile(inboxId: "1", name: "A", username: "a", avatar: nil)
        try await writer.add(profile: firstProfile)
        let second = await conversationIterator.next()
        #expect(second??.members == [firstProfile.hydrateProfile()])
        try await writer.remove(profile: firstProfile)
        let third = await conversationIterator.next()
        #expect(third??.members.isEmpty ?? false)
    }

    @Test("Removing a member changes conversation kind (dm or group)")
    func testRemovingMemberChangesConversationKind() async throws {
        let client = try await clientHolder.get()
        let messaging = client.messaging
        let state = try await messaging
            .messagingStatePublisher()
            .waitForFirstMatch { $0 == .ready }
        #expect(state == .ready)
        let composer = messaging.draftConversationComposer()
        let writer = composer.draftConversationWriter
        let repository = composer.draftConversationRepository
        var conversationIterator = repository.conversationPublisher
            .values
            .makeAsyncIterator()
        _ = await conversationIterator.next() // ignore first
        let firstProfile = MemberProfile(inboxId: "1", name: "A", username: "a", avatar: nil)
        try await writer.add(profile: firstProfile)
        let second = await conversationIterator.next()
        #expect(second??.kind == .dm)
        let secondProfile = MemberProfile(inboxId: "2", name: "B", username: "b", avatar: nil)
        try await writer.add(profile: secondProfile)
        let third = await conversationIterator.next()
        #expect(third??.kind == .group)
        try await writer.remove(profile: firstProfile)
        let fourth = await conversationIterator.next()
        #expect(fourth??.kind == .dm)
    }

    @Test("Sending a message creates the conversation on XMTP")
    func testSendingMessageCreatesConversation() async throws {
        let inboxId = try await registerTemporaryInboxId()
        let client = try await clientHolder.get()
        let messaging = client.messaging
        let state = try await messaging
            .messagingStatePublisher()
            .waitForFirstMatch { $0 == .ready }
        #expect(state == .ready)
        let composer = messaging.draftConversationComposer()
        let writer = composer.draftConversationWriter
        let repository = composer.draftConversationRepository
        var conversationIterator = repository.conversationPublisher
            .values
            .makeAsyncIterator()
        _ = await conversationIterator.next() // ignore first
        let messagesRepoPublisher = composer.draftConversationRepository.messagesRepositoryPublisher
        var messagesRepoIterator = messagesRepoPublisher.values.makeAsyncIterator()
        let firstProfile = MemberProfile(inboxId: inboxId, name: "A", username: "a", avatar: nil)
        try await writer.add(profile: firstProfile)
        let second = await conversationIterator.next()
        #expect(second??.kind == .dm)
        try await writer.send(text: "GM!")
        guard let messagesRepo = await messagesRepoIterator.next() else {
            fatalError("No messages repository")
        }
        let messagesPublisher = messagesRepo.messagesPublisher()
        var messagesIterator = messagesPublisher.values.makeAsyncIterator()
        _ = await messagesIterator.next() // ignore first (from init)
        _ = await messagesIterator.next() // ignore second (from draft creation)
        guard let messages = await messagesIterator.next() else {
            fatalError()
        }
        #expect(messages.count == 1)
        if case .update(_) = messages.first?.base.content {
            #expect(true)
        } else {
            #expect(Bool(false), "Welcome message not received")
        }
        let secondMessages = try await messagesPublisher
            .waitForFirstMatch(where: { $0.count == 2})
        #expect(secondMessages.count == 2)
        #expect(secondMessages.last?.base.content == .text("GM!"))
    }

    @Test("Adding members that have an existing conversation")
    func testAddingMembersWithExistingConversation() async throws {
        // the conversation should be used in the conversation repository
    }

    @Test("Selecting a conversation adds members")
    func testSelectingConversationAddsMembers() async throws {        
    }
}
