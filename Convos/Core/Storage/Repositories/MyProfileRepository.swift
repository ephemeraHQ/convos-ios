import Combine
import Foundation
import GRDB

protocol MyProfileRepositoryProtocol {
    var myProfilePublisher: AnyPublisher<Profile, Never> { get }

    func fetch(inboxId: String) throws -> Profile
}

class MyProfileRepository: MyProfileRepositoryProtocol {
    let myProfilePublisher: AnyPublisher<Profile, Never>

    private let databaseReader: any DatabaseReader

    init(
        inboxReadyValue: PublisherValue<InboxReadyResult>,
        databaseReader: any DatabaseReader
    ) {
        self.databaseReader = databaseReader
        self.myProfilePublisher = inboxReadyValue.publisher
            .compactMap { $0 }
            .map { inboxReady in
                let inboxId = inboxReady.client.inboxId
                return ValueObservation
                    .tracking { db in
                        try MemberProfile
                            .fetchOne(db, key: inboxId)?
                            .hydrateProfile() ?? .empty(inboxId: inboxId)
                    }
                    .publisher(in: databaseReader)
                    .replaceError(with: .empty(inboxId: inboxId))
                    .eraseToAnyPublisher()
            }
            .switchToLatest()
            .eraseToAnyPublisher()
    }

    func fetch(inboxId: String) throws -> Profile {
        try databaseReader.read { db in
            try MemberProfile
                .fetchOne(db, key: inboxId)?
                .hydrateProfile() ?? .empty(inboxId: inboxId)
        }
    }
}
