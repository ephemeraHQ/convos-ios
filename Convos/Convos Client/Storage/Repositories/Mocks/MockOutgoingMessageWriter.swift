import Combine
import Foundation

class MockOutgoingMessageWriter: OutgoingMessageWriterProtocol {
    let canSend: Bool = true
    var canSendPublisher: AnyPublisher<Bool, Never> { Just(true).eraseToAnyPublisher() }

    func send(text: String) async throws {
    }
}
