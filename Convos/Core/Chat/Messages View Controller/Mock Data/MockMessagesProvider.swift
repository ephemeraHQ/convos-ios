import Combine
import Foundation
import UIKit

// swiftlint:disable force_unwrapping

final class MockMessagesService: ConvosSDK.MessagingServiceProtocol {
    typealias RawMessage = MockMessage

    private var messagingStateSubject: CurrentValueSubject<ConvosSDK.MessagingServiceState, Never> =
    CurrentValueSubject<ConvosSDK.MessagingServiceState, Never>(.uninitialized)
    private var messagesSubject: CurrentValueSubject<[RawMessage], Never> =
    CurrentValueSubject<[RawMessage], Never>([])

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

    func loadInitialMessages() async -> [RawMessage] {
        let messages = createBunchOfMessages(number: 20)
        messagesSubject.value.append(contentsOf: messages)
        return messagesSubject.value
    }

    func loadPreviousMessages() async -> [RawMessage] {
        let messages = createBunchOfMessages(number: 20)
        messagesSubject.value.append(contentsOf: messages)
        return messagesSubject.value
    }

    func sendMessage(to address: String, content: String) async throws -> [RawMessage] {
        messagesSubject.value.append(MockMessage.message(content, sender: currentUser))
        return messagesSubject.value
    }

    func messages(for address: String) -> AnyPublisher<[RawMessage], Never> {
        messagesSubject.eraseToAnyPublisher()
    }

    func messagingStatePublisher() -> AnyPublisher<ConvosSDK.MessagingServiceState, Never> {
        messagingStateSubject.eraseToAnyPublisher()
    }

    private let currentUser: ConvosUser
    let otherUsers: [ConvosUser] = [
        ConvosUser(id: "1", name: "Emily Dickinson"),
        ConvosUser(id: "2", name: "William Shakespeare"),
        ConvosUser(id: "3", name: "Virginia Woolf"),
        ConvosUser(id: "4", name: "James Joyce"),
        ConvosUser(id: "5", name: "Oscar Wilde")
    ]

    private var allUsers: [ConvosUser] {
        [currentUser] + otherUsers
    }

    // MARK: - User Access

    var users: (current: ConvosUser, others: [ConvosUser]) {
        (currentUser, otherUsers)
    }

    // MARK: - Private Properties

    private var messageTimer: Timer?
    private var startingTimestamp: Double = Date().timeIntervalSince1970
    private let enableNewMessages: Bool = true

    private let websiteUrls: [URL] = [
        URL(string: "https://ephemerahq.com")!,
        URL(string: "https://xmtp.org"),
    ].compactMap { $0 }

    // swiftlint:disable line_length
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
    // swiftlint:enable line_length

    // MARK: - Initialization

    init(currentUser: ConvosUser) {
        self.currentUser = currentUser
        restartMessageTimer()
    }

    @objc
    private func handleTimer() {
        guard enableNewMessages else {
            return
        }
        let message = createRandomMessage()
        messagesSubject.value.append(message)
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

    private func createRandomMessage(date: Date = Date()) -> MockMessage {
        let sender = allUsers[Int.random(in: 0..<allUsers.count)]
        return MockMessage(id: UUID().uuidString,
                           content: TextGenerator.getString(of: Int.random(in: 1...20)),
                           sender: sender,
                           timestamp: date,
                           replies: [])
    }

    private func createBunchOfMessages(number: Int = 50) -> [RawMessage] {
        let messages = (0..<number).map { _ -> RawMessage in
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

// swiftlint:enable force_unwrapping
