import Combine
import Foundation

final class MockMessagingService: TempMessagingServiceProtocol {
    var updates: AnyPublisher<MessagingServiceUpdate, Never> {
        updatesPublisher
            .compactMap { $0 }
            .eraseToAnyPublisher()
    }
    private var updatesPublisher: CurrentValueSubject<MessagingServiceUpdate?, Never> = .init(nil)

    private let dataProvider: MessagesProviderProtocol
    private var typingState: TypingState = .idle
    private var lastReadUUID: UUID?
    private var lastReceivedUUID: UUID?
    private let userId: String

    private let currentUser: ConvosUser
    private let otherUsers: [ConvosUser]

    private var userMap: [String: ConvosUser] {
        var map: [String: ConvosUser] = [currentUser.id: currentUser]
        otherUsers.forEach { map[$0.id] = $0 }
        return map
    }

    var messages: [RawMessage] = []

    init() {
        let convosUser = ConvosUser(id: "0", name: "You")
        let provider = MockMessagesProvider(currentUser: convosUser)
        self.dataProvider = provider
        self.userId = convosUser.id

        // Get users from the provider if it's a MockMessagesProvider, otherwise use defaults
        if let mockProvider = dataProvider as? MockMessagesProvider {
            let users = mockProvider.users
            self.currentUser = users.current
            self.otherUsers = users.others
        } else {
            self.currentUser = ConvosUser(id: userId, name: "You")
            self.otherUsers = []
        }
        provider.delegate = self
    }

    func loadInitialMessages() async -> [Section] {
        let messages = await dataProvider.loadInitialMessages()
        appendConvertingToMessages(messages)
        await markAllMessagesAsReceived()
        await markAllMessagesAsRead()
        return await propagateLatestMessages()
    }

    func loadPreviousMessages() async -> [Section] {
        let messages = await dataProvider.loadPreviousMessages()
        appendConvertingToMessages(messages)
        await markAllMessagesAsReceived()
        await markAllMessagesAsRead()
        return await propagateLatestMessages()
    }

    func sendMessage(_ data: Message.Data) async -> [Section] {
        messages.append(RawMessage(id: UUID(), date: Date(), data: convert(data), userId: userId))
        return await propagateLatestMessages()
    }

    private func appendConvertingToMessages(_ rawMessages: [RawMessage]) {
        var messages = messages
        messages.append(contentsOf: rawMessages)
        self.messages = messages.sorted(by: { $0.date.timeIntervalSince1970 < $1.date.timeIntervalSince1970 })
    }

    private func propagateLatestMessages() async -> [Section] {
        var lastMessageStorage: Message?

        let messages = self.messages
            .map { rawMessage in
                Message(id: rawMessage.id,
                        date: rawMessage.date,
                        data: self.convert(rawMessage.data),
                        owner: userMap[rawMessage.userId] ?? ConvosUser(id: rawMessage.userId, name: "Unknown User"),
                        type: rawMessage.userId == self.userId ? .outgoing : .incoming,
                        status: rawMessage.status)
            }

        let messagesSplitByDay = messages
            .reduce(into: [[Message]]()) { result, message in
                guard var section = result.last,
                      let prevMessage = section.last else {
                    let section = [message]
                    result.append(section)
                    return
                }
                if Calendar.current.isDate(prevMessage.date, equalTo: message.date, toGranularity: .hour) {
                    section.append(message)
                    result[result.count - 1] = section
                } else {
                    let section = [message]
                    result.append(section)
                }
            }

        var cells: [Cell] = Array(messages.enumerated().map { index, message -> [Cell] in
            let bubble: Cell.BubbleType
            if index < messages.count - 1 {
                let nextMessage = messages[index + 1]
                bubble = nextMessage.owner.id == message.owner.id ? .normal : .tailed
            } else {
                bubble = .tailed
            }

            let ownerName = message.type == .outgoing ? "" : "\(message.owner.name)"
            let titleCell = Cell.messageGroup(MessageGroup(id: message.id, title: ownerName, type: message.type))

            if let lastMessage = lastMessageStorage {
                if lastMessage.owner.id != message.owner.id {
                    lastMessageStorage = message
                    return [titleCell, .message(message, bubbleType: bubble)]
                } else {
                    lastMessageStorage = message
                    return [.message(message, bubbleType: bubble)]
                }
            } else {
                lastMessageStorage = message
                return [titleCell, .message(message, bubbleType: bubble)]
            }
        }.joined())

        if let firstMessage = messages.first {
            let dateCell = Cell.date(DateGroup(id: firstMessage.id, date: firstMessage.date))
            cells.insert(dateCell, at: 0)
        }

        if typingState == .typing, !messagesSplitByDay.isEmpty {
            cells.append(.typingIndicator)
        }

        return [Section(id: 0, title: "", cells: Array(cells))]
    }

    private func markAllMessagesAsReceived() async {
        guard let lastReceivedUUID else { return }

        var finished = false
        messages = messages.map { message in
            guard !finished, message.status != .delivered, message.status != .read else {
                if message.id == lastReceivedUUID {
                    finished = true
                }
                return message
            }
            var message = message
            message.status = .delivered
            if message.id == lastReceivedUUID {
                finished = true
            }
            return message
        }
    }

    private func markAllMessagesAsRead() async {
        guard let lastReadUUID else { return }

        var finished = false
        messages = messages.map { message in
            guard !finished, message.status != .read else {
                if message.id == lastReadUUID {
                    finished = true
                }
                return message
            }
            var message = message
            message.status = .read
            if message.id == lastReadUUID {
                finished = true
            }
            return message
        }
    }

    private func convert(_ data: Message.Data) -> RawMessage.Data {
        switch data {
        case let .image(source, isLocallyStored: _):
            .image(source)
        case let .text(text):
            .text(text)
        }
    }

    private func convert(_ data: RawMessage.Data) -> Message.Data {
        switch data {
        case let .image(source):
                return .image(source, isLocallyStored: source.isLocal)
        case let .text(text):
            return .text(text)
        }
    }
}

extension MockMessagingService: MockMessagesProviderDelegate {
    func received(messages: [RawMessage]) {
        appendConvertingToMessages(messages)
        Task {
            await markAllMessagesAsReceived()
            await markAllMessagesAsRead()
            let sections = await propagateLatestMessages()
            updatesPublisher.send(.init(sections: sections, requiresIsolatedProcess: false))
        }
    }

    func typingStateChanged(to state: TypingState) {
        typingState = state
        Task {
            let sections = await propagateLatestMessages()
            updatesPublisher.send(.init(sections: sections, requiresIsolatedProcess: false))
        }
    }

    func lastReadIdChanged(to id: UUID) {
        lastReadUUID = id
        Task {
            await markAllMessagesAsRead()
            let sections = await propagateLatestMessages()
            updatesPublisher.send(.init(sections: sections, requiresIsolatedProcess: false))
        }
    }

    func lastReceivedIdChanged(to id: UUID) {
        lastReceivedUUID = id
        Task {
            await markAllMessagesAsReceived()
            let sections = await propagateLatestMessages()
            updatesPublisher.send(.init(sections: sections, requiresIsolatedProcess: false))
        }
    }
}
