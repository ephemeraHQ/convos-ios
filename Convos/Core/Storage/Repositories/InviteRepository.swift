import Combine
import Foundation
import GRDB

protocol InviteRepositoryProtocol {
    var invitePublisher: AnyPublisher<Invite?, Never> { get }
}

class InviteRepository: InviteRepositoryProtocol {
    lazy var invitePublisher: AnyPublisher<Invite?, Never> = {
        conversationIdPublisher
            .map { [databaseReader] conversationId in
                ValueObservation
                    .tracking { [weak self] db in
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
    }()

    private let databaseReader: any DatabaseReader
    private let conversationIdPublisher: AnyPublisher<String, Never>

    init(databaseReader: any DatabaseReader,
         conversationId: String,
         conversationIdPublisher: AnyPublisher<String, Never>) {
        self.databaseReader = databaseReader
        self.conversationIdPublisher = conversationIdPublisher
    }
}
