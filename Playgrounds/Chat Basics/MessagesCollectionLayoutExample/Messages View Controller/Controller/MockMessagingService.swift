import Foundation

final class MockMessagingService: MessagingServiceProtocol {
    weak var delegate: MessagesControllerDelegate?

    private let dataProvider: MessagesProviderProtocol
    @MainActor private var typingState: TypingState = .idle
    @MainActor private var lastReadUUID: UUID?
    @MainActor private var lastReceivedUUID: UUID?
    private let userId: Int

    private let currentUser: User
    private let otherUsers: [User]

    private var userMap: [Int: User] {
        var map: [Int: User] = [currentUser.id: currentUser]
        otherUsers.forEach { map[$0.id] = $0 }
        return map
    }

    @MainActor var messages: [RawMessage] = []

    init(dataProvider: MessagesProviderProtocol, userId: Int) {
        self.dataProvider = dataProvider
        self.userId = userId

        // Get users from the provider if it's a MockMessagesProvider, otherwise use defaults
        if let mockProvider = dataProvider as? MockMessagesProvider {
            let users = mockProvider.users
            self.currentUser = users.current
            self.otherUsers = users.others
        } else {
            self.currentUser = User(id: userId, name: "You")
            self.otherUsers = []
        }
    }

    @MainActor
    func loadInitialMessages() async -> [Section] {
        let messages = await dataProvider.loadInitialMessages()
        appendConvertingToMessages(messages)
        await markAllMessagesAsReceived()
        await markAllMessagesAsRead()
        return await propagateLatestMessages()
    }

    @MainActor
    func loadPreviousMessages() async -> [Section] {
        let messages = await dataProvider.loadPreviousMessages()
        appendConvertingToMessages(messages)
        await markAllMessagesAsReceived()
        await markAllMessagesAsRead()
        return await propagateLatestMessages()
    }

    @MainActor
    func sendMessage(_ data: Message.Data) async -> [Section] {
        messages.append(RawMessage(id: UUID(), date: Date(), data: convert(data), userId: userId))
        return await propagateLatestMessages()
    }

    @MainActor
    private func appendConvertingToMessages(_ rawMessages: [RawMessage]) {
        var messages = messages
        messages.append(contentsOf: rawMessages)
        self.messages = messages.sorted(by: { $0.date.timeIntervalSince1970 < $1.date.timeIntervalSince1970 })
    }

    @MainActor
    private func propagateLatestMessages() async -> [Section] {
        var lastMessageStorage: Message?

        let messages = self.messages
            .map { rawMessage in
                Message(id: rawMessage.id,
                       date: rawMessage.date,
                       data: self.convert(rawMessage.data),
                       owner: userMap[rawMessage.userId] ?? User(id: rawMessage.userId, name: "Unknown User"),
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

        if typingState == .typing,
           messagesSplitByDay.count > 0 {
            cells.append(.typingIndicator)
        }

        return [Section(id: 0, title: "", cells: Array(cells))]
    }

    @MainActor
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

    @MainActor
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
    @MainActor
    func received(messages: [RawMessage]) {
        appendConvertingToMessages(messages)
        Task {
            await markAllMessagesAsReceived()
            await markAllMessagesAsRead()
            let sections = await propagateLatestMessages()
            delegate?.update(with: sections, requiresIsolatedProcess: false)
        }
    }

    @MainActor
    func typingStateChanged(to state: TypingState) {
        typingState = state
        Task {
            let sections = await propagateLatestMessages()
            delegate?.update(with: sections, requiresIsolatedProcess: false)
        }
    }

    @MainActor
    func lastReadIdChanged(to id: UUID) {
        lastReadUUID = id
        Task {
            await markAllMessagesAsRead()
            let sections = await propagateLatestMessages()
            delegate?.update(with: sections, requiresIsolatedProcess: false)
        }
    }

    @MainActor
    func lastReceivedIdChanged(to id: UUID) {
        lastReceivedUUID = id
        Task {
            await markAllMessagesAsReceived()
            let sections = await propagateLatestMessages()
            delegate?.update(with: sections, requiresIsolatedProcess: false)
        }
    }
}
