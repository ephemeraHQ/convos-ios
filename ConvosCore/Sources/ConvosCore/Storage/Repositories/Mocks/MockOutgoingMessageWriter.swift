import Combine
import Foundation

public class MockOutgoingMessageWriter: OutgoingMessageWriterProtocol {
    public init() {}

    public var isSendingPublisher: AnyPublisher<Bool, Never> {
        Just(false).eraseToAnyPublisher()
    }

    public var sentMessage: AnyPublisher<String, Never> {
        Just("").eraseToAnyPublisher()
    }

    public func send(text: String) async throws {
    }
}
