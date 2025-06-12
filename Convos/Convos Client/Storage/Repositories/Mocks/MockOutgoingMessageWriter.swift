import Combine
import Foundation

class MockOutgoingMessageWriter: OutgoingMessageWriterProtocol {
    var isSendingPublisher: AnyPublisher<Bool, Never> {
        Just(false).eraseToAnyPublisher()
    }

    var sentMessage: AnyPublisher<String, Never> {
        Just("").eraseToAnyPublisher()
    }

    func send(text: String) async throws {
    }
}
