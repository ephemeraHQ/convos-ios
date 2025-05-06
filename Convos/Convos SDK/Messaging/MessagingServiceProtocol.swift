import Combine
import Foundation

public extension ConvosSDK {
    protocol RawMessageType {
        var id: String { get }
        var content: String { get }
        var sender: User { get }
        var timestamp: Date { get }
        var replies: [RawMessageType] { get }
    }

    protocol MessagingServiceProtocol {
        associatedtype RawMessage: RawMessageType

        func start() async throws
        func stop() async

        func sendMessage(to address: String, content: String) async throws -> [RawMessage]
        func messages(for address: String) -> AnyPublisher<[RawMessage], Never>
        func messagingStatePublisher() -> AnyPublisher<MessagingServiceState, Never>
        func loadInitialMessages() async -> [RawMessage]
        func loadPreviousMessages() async -> [RawMessage]
        var state: MessagingServiceState { get }
    }

    enum MessagingServiceState {
        case uninitialized
        case initializing
        case authorizing
        case ready
        case stopping
        case error(Error)
    }
}

struct MockMessage: ConvosSDK.RawMessageType {
    var id: String
    var content: String
    var sender: any ConvosSDK.User
    var timestamp: Date
    var replies: [any ConvosSDK.RawMessageType]

    static func message(_ content: String, sender: any ConvosSDK.User) -> MockMessage {
        .init(
            id: UUID().uuidString,
            content: content,
            sender: sender,
            timestamp: Date(),
            replies: []
        )
    }
}

class MockMessagingService: ConvosSDK.MessagingServiceProtocol {
    typealias RawMessage = MockMessage

    private var messagingStateSubject: CurrentValueSubject<ConvosSDK.MessagingServiceState, Never> =
    CurrentValueSubject<ConvosSDK.MessagingServiceState, Never>(.uninitialized)
    private var messagesSubject: CurrentValueSubject<[RawMessage], Never> =
    CurrentValueSubject<[RawMessage], Never>([])

    var state: ConvosSDK.MessagingServiceState {
        messagingStateSubject.value
    }

    func start() async throws {
    }

    func stop() {
    }

    func loadInitialMessages() async -> [RawMessage] {
        return []
    }

    func loadPreviousMessages() async -> [RawMessage] {
        return []
    }

    func sendMessage(to address: String, content: String) async throws -> [RawMessage] {
        messagesSubject.send([MockMessage.message(content, sender: MockUser())])
        return messagesSubject.value
    }

    func messages(for address: String) -> AnyPublisher<[RawMessage], Never> {
        messagesSubject.eraseToAnyPublisher()
    }

    func messagingStatePublisher() -> AnyPublisher<ConvosSDK.MessagingServiceState, Never> {
        messagingStateSubject.eraseToAnyPublisher()
    }
}
