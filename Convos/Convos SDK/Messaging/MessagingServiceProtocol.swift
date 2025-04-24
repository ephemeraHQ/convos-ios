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

class MockMessagingService: ConvosSDK.MessagingServiceProtocol {
    private var messagesSubject: CurrentValueSubject<[ConvosSDK.Message], Never> = .init([])

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
}
