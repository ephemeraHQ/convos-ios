import Combine
import Foundation
import UIKit

final class MockMessagesService: ConvosSDK.MessagingServiceProtocol {
    private var messagingStateSubject: CurrentValueSubject<ConvosSDK.MessagingServiceState, Never> =
    CurrentValueSubject<ConvosSDK.MessagingServiceState, Never>(.uninitialized)
    var clientPublisher: AnyPublisher<(any XMTPClientProvider)?, Never> {
        Just(nil).eraseToAnyPublisher()
    }

    var state: ConvosSDK.MessagingServiceState {
        messagingStateSubject.value
    }

    func start() async throws {
        await MainActor.run {
            self.messageTimer = Timer.scheduledTimer(
                timeInterval: TimeInterval(Int.random(in: 0...6)),
                target: self,
                selector: #selector(self.handleTimer),
                userInfo: nil,
                repeats: true
            )
        }
    }

    func stop() {
        messageTimer?.invalidate()
        messageTimer = nil
    }

    func userRepository() -> any UserRepositoryProtocol {
        MockUserRepository()
    }

    func profileSearchRepository() -> any ProfileSearchRepositoryProtocol {
        MockProfileSearchRepository()
    }

    func conversationsRepository() -> any ConversationsRepositoryProtocol {
        MockConversationsRepository()
    }

    func conversationRepository(for conversationId: String) -> any ConversationRepositoryProtocol {
        MockConversationRepository()
    }

    func messagesRepository(for conversationId: String) -> any MessagesRepositoryProtocol {
        MockMessagesRepository(conversation: .mock())
    }

    func messageWriter(for conversationId: String) -> any OutgoingMessageWriterProtocol {
        MockOutgoingMessageWriter()
    }

    func messagingStatePublisher() -> AnyPublisher<ConvosSDK.MessagingServiceState, Never> {
        messagingStateSubject.eraseToAnyPublisher()
    }

    private let currentUser: MockUser
    let otherUsers: [Profile] = [
        .mock(name: "Emily Dickinson"),
        .mock(name: "William Shakespeare"),
        .mock(name: "Virginia Woolf"),
        .mock(name: "James Joyce"),
        .mock(name: "Oscar Wilde")
    ]

    private var allUsers: [Profile] {
        [currentUser.profile] + otherUsers
    }

    // MARK: - User Access

    // MARK: - Private Properties

    private var messageTimer: Timer?
    private var startingTimestamp: Double = Date().timeIntervalSince1970
    private let enableNewMessages: Bool = true

    // swiftlint:disable line_length force_unwrapping
    private let websiteUrls: [URL] = [
        URL(string: "https://ephemerahq.com")!,
        URL(string: "https://xmtp.org"),
    ].compactMap { $0 }

    private let imageUrls: [URL] = [
        URL(string: "https://upload.wikimedia.org/wikipedia/commons/5/56/Black-white_photograph_of_Emily_Dickinson2.png")!,
        URL(string: "https://upload.wikimedia.org/wikipedia/commons/thumb/2/21/William_Shakespeare_by_John_Taylor%2C_edited.jpg/1920px-"
            + "William_Shakespeare_by_John_Taylor%2C_edited.jpg")!,
        URL(string: "https://upload.wikimedia.org/wikipedia/commons/thumb/0/0b/George_Charles_Beresford-"
            + "_Virginia_Woolf_in_1902_-_Restoration.jpg/1200px-George_Charles_Beresford-"
            + "_Virginia_Woolf_in_1902_-_Restoration.jpg")!,
        URL(string: "https://upload.wikimedia.org/wikipedia/commons/thumb/7/7f/Portrait_of_James_Joyce_P529.jpg/1920px-"
            + "Portrait_of_James_Joyce_P529.jpg")!
    ]
    // swiftlint:enable line_length force_unwrapping

    // MARK: - Initialization

    init(currentUser: MockUser) {
        self.currentUser = currentUser
        restartMessageTimer()
    }

    @objc
    private func handleTimer() {
        guard enableNewMessages else {
            return
        }
        let message = createRandomMessage()
//        messagesSubject.value.append(message)
        restartMessageTimer()
    }

    private func restartMessageTimer() {
        messageTimer?.invalidate()
        messageTimer = nil
        messageTimer = Timer
            .scheduledTimer(
                timeInterval: TimeInterval(Int.random(in: 0...6)),
                target: self,
                selector: #selector(handleTimer),
                userInfo: nil,
                repeats: true
            )
    }

    private func createRandomMessage(date: Date = Date()) -> any MessageType {
        let sender = allUsers[Int.random(in: 0..<allUsers.count)]
        return Message(
            id: UUID().uuidString,
            conversation: .mock(),
            sender: sender,
            source: .incoming,
            status: .published,
            content: .text(TextGenerator.getString(of: Int.random(in: 1...20))),
            reactions: []
        )
    }

    private func createBunchOfMessages(number: Int = 50) -> [any MessageType] {
        let messages = (0..<number).map { _ -> any MessageType in
            startingTimestamp -= TimeInterval(Int.random(in: 100...1000))
            return self.createRandomMessage(date: Date(timeIntervalSince1970: startingTimestamp))
        }
        return messages
    }

    private func randomDate(before endDate: Date) -> Date {
        let earliestTimeInterval: TimeInterval = 0.0
        let latestTimeInterval = endDate.timeIntervalSince1970

        // Generate a random time interval between 0 and endDate.timeIntervalSince1970
        let randomTimeInterval = TimeInterval.random(in: earliestTimeInterval..<latestTimeInterval)

        return Date(timeIntervalSince1970: randomTimeInterval)
    }
}
