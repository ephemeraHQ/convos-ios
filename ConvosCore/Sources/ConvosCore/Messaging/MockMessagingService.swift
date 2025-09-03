import Combine
import Foundation
import UIKit
import XMTPiOS

public class MockMessagingService: MessagingServiceProtocol {
    public let identifier: String

    public let currentUser: ConversationMember = .mock()
    public let allUsers: [ConversationMember]
    public let _conversations: [Conversation]

    private var unpublishedMessages: [AnyMessage] = []

    private var currentConversation: Conversation?
    private var messages: [AnyMessage]
    private var messagesSubject: CurrentValueSubject<[AnyMessage], Never>
    private var messageTimer: Timer?

    public init() {
        self.identifier = UUID().uuidString
        let users = Self.randomUsers()
        allUsers = users
        _conversations = Self.randomConversations(with: users)
        currentConversation = _conversations.randomElement()
        let initialMessages = Self.generateRandomMessages(
            count: Int.random(in: 5...50),
            conversation: currentConversation ?? _conversations[0],
            users: allUsers
        )
        self.messages = initialMessages
        self.messagesSubject = CurrentValueSubject(initialMessages)
    }

    // MARK: - Protocol Conformance

    public func stopAndDelete() {}

    public func stopAndDelete() async {}

    public func registerForPushNotifications() async {
        // Mock implementation - no-op
    }

    public func myProfileWriter() -> any MyProfileWriterProtocol {
        self
    }

    public func myProfileRepository() -> any MyProfileRepositoryProtocol {
        self
    }

    public func draftConversationComposer() -> any DraftConversationComposerProtocol {
        MockDraftConversationComposer()
    }

    public var clientPublisher: AnyPublisher<(any XMTPClientProvider)?, Never> {
        Just(self).eraseToAnyPublisher()
    }

    public func conversationsRepository(for consent: [Consent]) -> any ConversationsRepositoryProtocol {
        self
    }

    public func conversationsCountRepo(for consent: [Consent], kinds: [ConversationKind]) -> any ConversationsCountRepositoryProtocol {
        self
    }

    public func conversationRepository(for conversationId: String) -> any ConversationRepositoryProtocol {
        if let found = _conversations.first(where: { $0.id == conversationId }) {
            currentConversation = found
        }
        return self
    }

    public func conversationConsentWriter() -> any ConversationConsentWriterProtocol {
        self
    }

    public func messagesRepository(for conversationId: String) -> any MessagesRepositoryProtocol {
        if let found = _conversations.first(where: { $0.id == conversationId }) {
            currentConversation = found
        }
        return self
    }

    public func inviteRepository(for conversationId: String) -> any InviteRepositoryProtocol {
        self
    }

    public func messageWriter(for conversationId: String) -> any OutgoingMessageWriterProtocol {
        self
    }

    public func conversationLocalStateWriter() -> any ConversationLocalStateWriterProtocol {
        MockConversationLocalStateWriter()
    }

    public func groupMetadataWriter() -> any ConversationMetadataWriterProtocol {
        MockGroupMetadataWriter()
    }

    public func groupPermissionsRepository() -> any GroupPermissionsRepositoryProtocol {
        MockGroupPermissionsRepository()
    }

    public func uploadImage(data: Data, filename: String) async throws -> String {
        // Return a mock URL for testing
        return "https://example.com/uploads/\(filename)"
    }

    public func uploadImageAndExecute(
        data: Data,
        filename: String,
        afterUpload: @escaping (String) async throws -> Void
    ) async throws -> String {
        let uploadedURL = "https://example.com/uploads/\(filename)"
        try await afterUpload(uploadedURL)
        return uploadedURL
    }
}

extension MockMessagingService: InviteRepositoryProtocol {
    public var invitePublisher: AnyPublisher<Invite?, Never> {
        Just(.mock()).eraseToAnyPublisher()
    }
}

extension MockMessagingService: MyProfileWriterProtocol {
    public func update(displayName: String) {
    }

    public func update(avatar: UIImage?) async throws {
    }
}

extension MockMessagingService: MyProfileRepositoryProtocol {
    public var myProfilePublisher: AnyPublisher<Profile, Never> {
        Just(currentUser.profile).eraseToAnyPublisher()
    }

    public func fetch(inboxId: String) throws -> Profile {
        .mock()
    }
}

extension MockMessagingService: ConversationsRepositoryProtocol {
    public var conversationsPublisher: AnyPublisher<[Conversation], Never> {
        Just(_conversations).eraseToAnyPublisher()
    }

    public func fetchAll() throws -> [Conversation] {
        _conversations
    }
}

extension MockMessagingService: ConversationsCountRepositoryProtocol {
    public var conversationsCount: AnyPublisher<Int, Never> {
        Just(1).eraseToAnyPublisher()
    }

    public func fetchCount() throws -> Int {
        1
    }
}

extension MockMessagingService: ConversationConsentWriterProtocol {
    public func join(conversation: Conversation) async throws {
    }

    public func delete(conversation: Conversation) async throws {
    }

    public func deleteAll() async throws {
    }
}

extension MockMessagingService: ConversationRepositoryProtocol {
    public var conversationId: String {
        conversation?.id ?? ""
    }

    public var conversation: Conversation? {
        _conversations.randomElement()
    }

    public var conversationPublisher: AnyPublisher<Conversation?, Never> {
        Just(conversation).eraseToAnyPublisher()
    }

    public func fetchConversation() throws -> Conversation? {
        conversation
    }
}

extension MockMessagingService: MessagesRepositoryProtocol {
    public var messagesPublisher: AnyPublisher<[AnyMessage], Never> {
        messagesSubject.eraseToAnyPublisher()
    }

    public func fetchAll() throws -> [AnyMessage] {
        messages
    }

    public var conversationMessagesPublisher: AnyPublisher<ConversationMessages, Never> {
        let conversationId = currentConversation?.id ?? ""
        return messagesSubject
            .map { (conversationId, $0) }
            .eraseToAnyPublisher()
    }
}

extension MockMessagingService: OutgoingMessageWriterProtocol {
    public var sentMessage: AnyPublisher<String, Never> {
        Just("").eraseToAnyPublisher()
    }

    public func send(text: String) async throws {
        _ = try await prepare(text: text)
        try await publish()
    }
}

extension MockMessagingService: ConversationSender {
    public var id: String {
        "conversationId"
    }

    public func add(members inboxIds: [String]) async throws {
    }

    public func remove(members inboxIds: [String]) async throws {
    }
}

class MockConversations: ConversationsProvider {
    func listGroups(createdAfter: Date?, createdBefore: Date?, limit: Int?, consentStates: [ConsentState]?) throws -> [XMTPiOS.Group] {
        []
    }

    func list(
        createdAfter: Date?,
        createdBefore: Date?,
        limit: Int?,
        consentStates: [XMTPiOS.ConsentState]?
    ) async throws -> [XMTPiOS.Conversation] {
        []
    }

    func stream(
        type: XMTPiOS.ConversationFilterType,
        onClose: (() -> Void)?
    ) -> AsyncThrowingStream<XMTPiOS.Conversation, any Error> {
        AsyncThrowingStream { _ in
        }
    }

    func syncAllConversations(consentStates: [XMTPiOS.ConsentState]?) async throws -> UInt32 {
        0
    }

    func findConversation(conversationId: String) async throws -> XMTPiOS.Conversation? {
        nil
    }

    func streamAllMessages(
        type: ConversationFilterType,
        consentStates: [ConsentState]?,
        onClose: (() -> Void)?
    ) -> AsyncThrowingStream<DecodedMessage, any Error> {
        AsyncThrowingStream { _ in
        }
    }
}

extension MockMessagingService: XMTPClientProvider {
    public func newConversation(with memberInboxId: String) async throws -> any MessageSender {
        self
    }

    public var installationId: String {
        ""
    }

    public var inboxId: String {
        ""
    }

    public func signWithInstallationKey(message: String) throws -> Data {
        Data()
    }

    public func canMessage(identity: String) async throws -> Bool {
        true
    }

    public func canMessage(identities: [String]) async throws -> [String: Bool] {
        return Dictionary(uniqueKeysWithValues: identities.map { ($0, true) })
    }

    public func prepareConversation() async throws -> ConversationSender {
        self
    }

    public func newConversation(with memberInboxIds: [String],
                                name: String,
                                description: String,
                                imageUrl: String) async throws -> String {
        return UUID().uuidString
    }

    public func newConversation(with memberInboxId: String) async throws -> String {
        return UUID().uuidString
    }

    public func conversation(with id: String) async throws -> XMTPiOS.Conversation? {
        nil
    }

    public var conversationsProvider: ConversationsProvider {
        MockConversations()
    }

    public func messageSender(for conversationId: String) async throws -> (any MessageSender)? {
        self
    }

    public func inboxId(for ethereumAddress: String) async throws -> String? {
        nil
    }

    public func update(consent: Consent, for conversationId: String) async throws {
    }

    public func deleteLocalDatabase() throws {
    }

    public func revokeInstallations(signingKey: any SigningKey, installationIds: [String]) async throws {
    }
}

extension MockMessagingService: MessageSender {
    public func prepare(text: String) async throws -> String {
        guard let conversation = currentConversation else { return "" }
        let message: AnyMessage = .message(
            .init(id: UUID().uuidString,
                  conversation: conversation,
                  sender: ConversationMember(profile: currentUser.profile, role: .member, isCurrentUser: true),
                  source: .outgoing,
                  status: .published,
                  content: .text(text),
                  date: Date(),
                  reactions: []
                 )
        )
        unpublishedMessages.append(message)
        return message.base.id
    }

    public func publish() async throws {
        messages.append(contentsOf: unpublishedMessages)
        unpublishedMessages.removeAll()
        messagesSubject.send(messages)
    }
}

// MARK: - Mock Data Generation

extension MockMessagingService {
    static func randomConversations(with users: [ConversationMember]) -> [Conversation] {
        (0..<Int.random(in: 10...50)).map { index in
            Self.generateRandomConversation(id: "\(index)", from: users)
        }
    }

    static func randomUsers() -> [ConversationMember] {
        [
            .mock(name: "Alice Johnson"),
            .mock(name: "Bob Smith"),
            .mock(name: "Carol Williams"),
            .mock(name: "David Brown"),
            .mock(name: "Emma Davis"),
            .mock(name: "Frank Miller"),
            .mock(name: "Grace Wilson"),
            .mock(name: "Henry Taylor"),
            .mock(name: "Isabella Martinez"),
            .mock(name: "James Anderson")
        ]
    }

    static func generateRandomConversation(id: String, from users: [ConversationMember]) -> Conversation {
        var availableUsers = users
        // swiftlint:disable:next force_unwrapping
        let randomCreator = availableUsers.randomElement()!
        availableUsers.removeAll { $0 == randomCreator }

        let isDirectMessage = Bool.random()
        let kind: ConversationKind = isDirectMessage ? .dm : .group

        let memberCount = isDirectMessage ? 1 : Int.random(in: 1..<availableUsers.count)
        // swiftlint:disable:next force_unwrapping
        let otherMember = isDirectMessage ? availableUsers.randomElement()! : nil
        // swiftlint:disable:next force_unwrapping
        let randomMembers = isDirectMessage ? [otherMember!, randomCreator] : Array(
            availableUsers.shuffled().prefix(memberCount)
        )

        // swiftlint:disable:next force_unwrapping
        let randomName = isDirectMessage ? otherMember!.profile.displayName : [
            "Team Discussion",
            "Project Planning",
            "Coffee Chat",
            "Weekend Plans",
            "Book Club",
            "Gaming Group",
            "Study Group"
        // swiftlint:disable:next force_unwrapping
        ].randomElement()!

        return .mock(
            id: id,
            creator: randomCreator,
            date: Date(),
            consent: id == "1" ? .allowed : Consent.allCases.randomElement() ?? .allowed,
            kind: kind,
            name: randomName,
            members: randomMembers,
            otherMember: otherMember,
            messages: [],
            lastMessage: .init(
                text: TextGenerator.getString(
                    of: Int.random(in: 1...10)),
                createdAt: Date().addingTimeInterval(-TimeInterval.random(in: 0...86400))
            )
        )
    }

    private func startMessageTimer() {
        messageTimer?.invalidate()
        scheduleNextMessage()
    }

    private func scheduleNextMessage() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let interval = TimeInterval.random(in: 0.0...2.0)
            messageTimer = Timer.scheduledTimer(
                timeInterval: interval,
                target: self,
                selector: #selector(handleTimer),
                userInfo: nil,
                repeats: false
            )
        }
    }

    @objc
    private func handleTimer() {
        generateRandomMessageAndAppend()
        scheduleNextMessage()
    }

    private func generateRandomMessageAndAppend() {
        guard let conversation = currentConversation ?? _conversations.first else { return }
        let sender = conversation.members.randomElement() ?? allUsers.randomElement() ?? currentUser
        let message = Message(
            id: UUID().uuidString,
            conversation: conversation,
            sender: sender,
            source: .incoming,
            status: .published,
            content: .text(TextGenerator.getString(of: Int.random(in: 1...20))),
            date: Date(),
            reactions: []
        )
        let anyMessage = AnyMessage.message(message)
        messages.append(anyMessage)
        messagesSubject.send(messages)
    }

    static func generateRandomMessages(
        count: Int,
        conversation: Conversation,
        users: [ConversationMember]
    ) -> [AnyMessage] {
        (0..<count).map { _ in
            let sender = conversation.members.randomElement() ?? users.randomElement() ?? users[0]
            let message = Message(
                id: UUID().uuidString,
                conversation: conversation,
                sender: sender,
                source: .incoming,
                status: .published,
                content: .text(TextGenerator.getString(of: Int.random(in: 1...20))),
                date: Date(),
                reactions: []
            )
            return AnyMessage.message(message)
        }
    }
}

// Add a mock implementation for ConversationLocalStateWriterProtocol
public class MockConversationLocalStateWriter: ConversationLocalStateWriterProtocol {
    public init() {}
    public func setUnread(_ isUnread: Bool, for conversationId: String) async throws {}
    public func setPinned(_ isPinned: Bool, for conversationId: String) async throws {}
    public func setMuted(_ isMuted: Bool, for conversationId: String) async throws {}
}

// Add mock implementations for group functionality
public class MockGroupMetadataWriter: ConversationMetadataWriterProtocol {
    public init() {}
    public func updateGroupName(groupId: String, name: String) async throws {}
    public func updateGroupDescription(groupId: String, description: String) async throws {}
    public func updateGroupImageUrl(groupId: String, imageURL: String) async throws {}
    public func addGroupMembers(groupId: String, memberInboxIds: [String]) async throws {}
    public func removeGroupMembers(groupId: String, memberInboxIds: [String]) async throws {}
    public func promoteToAdmin(groupId: String, memberInboxId: String) async throws {}
    public func demoteFromAdmin(groupId: String, memberInboxId: String) async throws {}
    public func promoteToSuperAdmin(groupId: String, memberInboxId: String) async throws {}
    public func demoteFromSuperAdmin(groupId: String, memberInboxId: String) async throws {}
    public func updateGroupImage(conversation: Conversation, image: UIImage) async throws {}
}

class MockGroupPermissionsRepository: GroupPermissionsRepositoryProtocol {
    func addAdmin(memberInboxId: String, to groupId: String) async throws {
        // @lourou
    }

    func removeAdmin(memberInboxId: String, from groupId: String) async throws {
        // @lourou
    }

    func addSuperAdmin(memberInboxId: String, to groupId: String) async throws {
        // @lourou
    }

    func removeSuperAdmin(memberInboxId: String, from groupId: String) async throws {
    }

    func addMembers(inboxIds: [String], to groupId: String) async throws {
    }

    func removeMembers(inboxIds: [String], from groupId: String) async throws {
    }

    func getGroupPermissions(for groupId: String) async throws -> GroupPermissionPolicySet {
        return GroupPermissionPolicySet.defaultPolicy
    }

    func getMemberRole(memberInboxId: String, in groupId: String) async throws -> MemberRole {
        return .member
    }

    func canPerformAction(
        memberInboxId: String,
        action: GroupPermissionAction,
        in groupId: String) async throws -> Bool {
        return true
    }

    func getGroupMembers(for groupId: String) async throws -> [GroupMemberInfo] {
        return []
    }
}
