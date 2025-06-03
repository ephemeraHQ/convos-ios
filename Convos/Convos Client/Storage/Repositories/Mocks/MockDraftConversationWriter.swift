import Combine
import Foundation

class MockDraftConversationWriter: DraftConversationWriterProtocol {
    var conversationIdPublisher: AnyPublisher<String, Never> { Just("").eraseToAnyPublisher() }

    func add(profile: MemberProfile) async throws {
    }

    func remove(profile: MemberProfile) async throws {
    }

    func send(text: String) async throws {
    }
}
