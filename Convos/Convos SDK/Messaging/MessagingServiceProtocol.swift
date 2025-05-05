import Combine
import Foundation

public extension ConvosSDK {
    protocol Message {
        var id: String { get }
        var content: String { get }
        var sender: User { get }
        var timestamp: Date { get }
    }

    protocol MessagingServiceProtocol {
        func start() async throws
        func stop() async

        func sendMessage(to address: String, content: String) async throws
        func messages(for address: String) -> AnyPublisher<[Message], Never>
        func messagingStatePublisher() -> AnyPublisher<MessagingServiceState, Never>
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

struct MockMessage: ConvosSDK.Message {
    var id: String
    var content: String
    var sender: any ConvosSDK.User
    var timestamp: Date

    static func message(_ content: String) -> MockMessage {
        .init(
            id: UUID().uuidString,
            content: content,
            sender: MockUser(),
            timestamp: Date()
        )
    }
}

class _MockMessagingService: ConvosSDK.MessagingServiceProtocol {
    private var messagingStateSubject: CurrentValueSubject<ConvosSDK.MessagingServiceState, Never> = .init(.uninitialized)
    private var messagesSubject: CurrentValueSubject<[ConvosSDK.Message], Never> = .init([])

    var state: ConvosSDK.MessagingServiceState {
        messagingStateSubject.value
    }

    func start() async throws {
    }

    func stop() {
    }

    func sendMessage(to address: String, content: String) async throws {
        messagesSubject.send([MockMessage.message(content)])
    }

    func messages(for address: String) -> AnyPublisher<[any ConvosSDK.Message], Never> {
        messagesSubject.eraseToAnyPublisher()
    }
    
    func messagingStatePublisher() -> AnyPublisher<ConvosSDK.MessagingServiceState, Never> {
        messagingStateSubject.eraseToAnyPublisher()
    }
}
