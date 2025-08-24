import Combine
import Foundation

class MockDraftConversationWriter: DraftConversationWriterProtocol {
    func createConversation() async throws {
    }

    func requestToJoin(inviteCode: String) async throws {
    }

    var conversationMetadataWriter: any ConversationMetadataWriterProtocol {
        MockGroupMetadataWriter()
    }

    var sentMessage: AnyPublisher<String, Never> {
        Just("").eraseToAnyPublisher()
    }

    var draftConversationId: String = ""

    var conversationId: String {
        UUID().uuidString
    }

    var conversationIdPublisher: AnyPublisher<String, Never> { Just(conversationId).eraseToAnyPublisher() }

    func add(profile: MemberProfile) async throws {
    }

    func remove(profile: MemberProfile) async throws {
    }

    func send(text: String) async throws {
    }

    func delete() async {
    }
}
