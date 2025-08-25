import Combine
import Foundation

public class MockOutgoingMessageWriter: OutgoingMessageWriterProtocol {
    public init() {}

    public var sentMessage: AnyPublisher<String, Never> {
        Just("").eraseToAnyPublisher()
    }

    public func send(text: String) async throws {
    }
}
