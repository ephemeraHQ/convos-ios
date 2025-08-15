import Combine
import Foundation

class MockDraftConversationWriter: DraftConversationWriterProtocol {
    public var conversationMetadataWriter: any ConversationMetadataWriterProtocol {
        MockGroupMetadataWriter()
    }

    public func requestToJoinWhenInboxReady(inviteCode: String) {}

    public var isSendingPublisher: AnyPublisher<Bool, Never> {
        Just(false).eraseToAnyPublisher()
    }

    public var sentMessage: AnyPublisher<String, Never> {
        Just("").eraseToAnyPublisher()
    }

    public var draftConversationId: String = ""

    public var conversationId: String {
        UUID().uuidString
    }

    public var conversationIdPublisher: AnyPublisher<String, Never> { Just(conversationId).eraseToAnyPublisher() }

    public func add(profile: MemberProfile) async throws {
    }

    public func remove(profile: MemberProfile) async throws {
    }

    public func send(text: String) async throws {
    }

    public func createConversationWhenInboxReady() {
    }
}
