import Combine
import Foundation

class MockDraftConversationWriter: DraftConversationWriterProtocol {
    var draftConversationId: String = ""

    var conversationId: String {
        UUID().uuidString
    }

    var sentMessage: AnyPublisher<String, Never> {
        Just("").eraseToAnyPublisher()
    }

    var isSendingPublisher: AnyPublisher<Bool, Never> {
        Just(false).eraseToAnyPublisher()
    }

    var conversationIdPublisher: AnyPublisher<String, Never> { Just(conversationId).eraseToAnyPublisher() }

    func add(profile: MemberProfile) async throws {
    }

    func remove(profile: MemberProfile) async throws {
    }

    func send(text: String) async throws {
    }
}
