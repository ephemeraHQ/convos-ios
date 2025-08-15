import Combine
import Foundation
import GRDB

protocol InviteRepositoryProtocol {
    var invitePublisher: AnyPublisher<Invite?, Never> { get }
}

class InviteRepository: InviteRepositoryProtocol {
    let invitePublisher: AnyPublisher<Invite?, Never>

    init(databaseReader: any DatabaseReader,
         conversationId: String,
         conversationIdPublisher: AnyPublisher<String, Never>) {
        self.invitePublisher = conversationIdPublisher
            .map { [databaseReader] conversationId in
                ValueObservation
                    .tracking { db in
                        try DBInvite
                            .filter(DBInvite.Columns.conversationId == conversationId)
                            .fetchOne(db)?
                            .hydrateInvite()
                    }
                    .publisher(in: databaseReader)
                    .replaceError(with: nil)
                    .eraseToAnyPublisher()
            }
            .switchToLatest()
            .eraseToAnyPublisher()
    }
}
