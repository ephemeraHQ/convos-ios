import Combine
import Foundation

protocol SessionManagerProtocol {
    var inboxesRepository: any InboxesRepositoryProtocol { get }

    func messagingServicePublisher(for inboxId: String) -> AnyPublisher<any MessagingServiceProtocol, Never>
    func conversationsRepository(for consent: [Consent]) -> any ConversationsRepositoryProtocol
    func conversationsCountRepo(for consent: [Consent]) -> any ConversationsCountRepositoryProtocol
}
