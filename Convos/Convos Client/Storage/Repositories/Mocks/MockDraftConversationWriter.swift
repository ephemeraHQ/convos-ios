import Combine
import Foundation

class MockDraftConversationWriter: DraftConversationWriterProtocol {
    var selectedConversationId: String?
    var canSend: Bool = true
    var canSendPublisher: AnyPublisher<Bool, Never> { Just(true).eraseToAnyPublisher() }

    func add(profile: MemberProfile) async throws {
    }

    func remove(profile: MemberProfile) async throws {
    }

    func send(text: String) async throws {
    }
}
