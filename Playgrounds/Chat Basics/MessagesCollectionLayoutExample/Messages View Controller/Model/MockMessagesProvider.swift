import Foundation
import UIKit

@MainActor
protocol MockMessagesProviderDelegate: AnyObject {
    func received(messages: [RawMessage])
    func typingStateChanged(to state: TypingState)
    func lastReadIdChanged(to id: UUID)
    func lastReceivedIdChanged(to id: UUID)
}

protocol MessagesProviderProtocol {
    func loadInitialMessages() async -> [RawMessage]
    func loadPreviousMessages() async -> [RawMessage]
    func stop()
}

final class MockMessagesProvider: MessagesProviderProtocol {
    weak var delegate: MockMessagesProviderDelegate?

    // MARK: - Mock Users

    private let currentUser: User
    private let otherUsers: [User] = [
        User(id: 1, name: "Emily Dickinson"),
        User(id: 2, name: "William Shakespeare"),
        User(id: 3, name: "Virginia Woolf"),
        User(id: 4, name: "James Joyce"),
        User(id: 5, name: "Oscar Wilde")
    ]

    private var allUsers: [User] {
        [currentUser] + otherUsers
    }

    // MARK: - User Access

    var users: (current: User, others: [User]) {
        (currentUser, otherUsers)
    }

    // MARK: - Private Properties

    private var messageTimer: Timer?
    private var typingTimer: Timer?
    private var startingTimestamp = Date().timeIntervalSince1970
    private var typingState: TypingState = .idle
    private var lastMessageIndex: Int = 0
    private var nextImageMessageIndex: Int = Int.random(in: 3...8)
    private var lastReadUUID: UUID?
    private var lastReceivedUUID: UUID?
    private let dispatchQueue = DispatchQueue.global(qos: .userInteractive)
    private let enableTyping = true
    private let enableNewMessages = true

    private let websiteUrls: [URL] = [
        URL(string: "https://ephemerahq.com")!,
        URL(string: "https://xmtp.org"),
    ].compactMap { $0 }

    private let imageUrls: [URL] = [
        URL(string: "https://upload.wikimedia.org/wikipedia/commons/5/56/Black-white_photograph_of_Emily_Dickinson2.png")!,
        URL(string: "https://upload.wikimedia.org/wikipedia/commons/thumb/2/21/William_Shakespeare_by_John_Taylor%2C_edited.jpg/1920px-William_Shakespeare_by_John_Taylor%2C_edited.jpg")!,
        URL(string: "https://upload.wikimedia.org/wikipedia/commons/thumb/0/0b/George_Charles_Beresford_-_Virginia_Woolf_in_1902_-_Restoration.jpg/1200px-George_Charles_Beresford_-_Virginia_Woolf_in_1902_-_Restoration.jpg")!,
        URL(string: "https://upload.wikimedia.org/wikipedia/commons/thumb/7/7f/Portrait_of_James_Joyce_P529.jpg/1920px-Portrait_of_James_Joyce_P529.jpg")!
    ]

    // MARK: - Initialization

    init(currentUser: User) {
        self.currentUser = currentUser

        messageTimer = Timer.scheduledTimer(timeInterval: TimeInterval(Int.random(in: 0...6)), target: self, selector: #selector(handleTimer), userInfo: nil, repeats: true)
        typingTimer = Timer.scheduledTimer(timeInterval: TimeInterval(Int.random(in: 0...6)), target: self, selector: #selector(handleTypingTimer), userInfo: nil, repeats: true)
    }

    func loadInitialMessages() async -> [RawMessage] {
        await withCheckedContinuation { continuation in
            dispatchQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: [])
                    return
                }
                let messages = createBunchOfMessages(number: 50)
                if messages.count > 10 {
                    lastReceivedUUID = messages[messages.count - 10].id
                }
                if messages.count > 3 {
                    lastReadUUID = messages[messages.count - 3].id
                }
                DispatchQueue.main.async {
                    continuation.resume(returning: messages)
                }
            }
        }
    }

    func loadPreviousMessages() async -> [RawMessage] {
        await withCheckedContinuation { continuation in
            dispatchQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: [])
                    return
                }
                let messages = createBunchOfMessages(number: 50)
                continuation.resume(returning: messages)
            }
        }
    }

    func stop() {
        messageTimer?.invalidate()
        messageTimer = nil
        typingTimer?.invalidate()
        typingTimer = nil
    }

    @objc
    private func handleTimer() {
        guard enableNewMessages else {
            return
        }
        let message = createRandomMessage()
        Task { @MainActor in
            delegate?.received(messages: [message])

            if message.userId != currentUser.id {
                if Int.random(in: 0...1) == 0 {
                    lastReceivedUUID = message.id
                    delegate?.lastReceivedIdChanged(to: message.id)
                }
                if Int.random(in: 0...3) == 0 {
                    lastReadUUID = lastReceivedUUID
                    lastReceivedUUID = message.id
                    delegate?.lastReadIdChanged(to: message.id)
                }
            }
        }

        restartMessageTimer()
        restartTypingTimer()
    }

    @objc
    private func handleTypingTimer() {
        guard enableTyping else {
            return
        }
        typingState = typingState == .idle ? TypingState.typing : .idle
        Task { @MainActor in
            delegate?.typingStateChanged(to: typingState)
        }
    }

    private func restartMessageTimer() {
        messageTimer?.invalidate()
        messageTimer = nil
        messageTimer = Timer.scheduledTimer(timeInterval: TimeInterval(Int.random(in: 0...6)), target: self, selector: #selector(handleTimer), userInfo: nil, repeats: true)
    }

    private func restartTypingTimer() {
        typingTimer?.invalidate()
        typingTimer = nil
        typingTimer = Timer.scheduledTimer(timeInterval: TimeInterval(Int.random(in: 1...3)), target: self, selector: #selector(handleTypingTimer), userInfo: nil, repeats: true)
    }

    private func createRandomMessage(date: Date = Date()) -> RawMessage {
        let sender = allUsers[Int.random(in: 0..<allUsers.count)]
        lastMessageIndex += 1
        if lastMessageIndex == nextImageMessageIndex {
            // Schedule next image message
            nextImageMessageIndex = lastMessageIndex + Int.random(in: 3...8)
            return RawMessage(
                id: UUID(),
                date: date,
                data: .image(.imageURL(imageUrls[Int.random(in: 0..<imageUrls.count)])),
                userId: sender.id)
        } else {
            return RawMessage(id: UUID(), date: date, data: .text(TextGenerator.getString(of: Int.random(in: 1...20))), userId: sender.id)
        }
    }

    private func createBunchOfMessages(number: Int = 50) -> [RawMessage] {
        let messages = (0..<number).map { _ -> RawMessage in
            startingTimestamp -= TimeInterval(Int.random(in: 100...1000))
            return self.createRandomMessage(date: Date(timeIntervalSince1970: startingTimestamp))
        }
        return messages
    }
}
