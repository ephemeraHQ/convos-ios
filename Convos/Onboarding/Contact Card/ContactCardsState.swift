import Combine
import SwiftUI

@Observable
class ContactCardsState {
    private let inboxesRepository: any InboxesRepositoryProtocol

    private var cancellable: AnyCancellable?
    private(set) var contactCards: [ContactCard]

    init(inboxesRepository: any InboxesRepositoryProtocol) {
        self.inboxesRepository = inboxesRepository
        self.contactCards = (try? inboxesRepository.allInboxes())?.contactCards() ?? []
        self.cancellable = inboxesRepository.inboxesPublisher
            .map { $0.contactCards() }
            .receive(on: DispatchQueue.main)
            .assign(to: \.contactCards, on: self)
    }
}

fileprivate extension Array where Element == Inbox {
    func contactCards() -> [ContactCard] {
        let standardInboxes = filter { $0.type == .standard }
        let ephemeralInboxes = filter {$0.type == .ephemeral }
        var contactCards: [ContactCard] = [
            .init(type: .cash([])),
            .init(type: .ephemeral(ephemeralInboxes))
        ]
        contactCards.append(contentsOf: standardInboxes.map { .init(type: .standard($0))})
        return contactCards
    }
}
