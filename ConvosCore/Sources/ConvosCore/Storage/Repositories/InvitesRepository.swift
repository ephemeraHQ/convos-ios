import Combine
import Foundation
import GRDB

protocol InvitesRepositoryProtocol {
    func fetchInvites(for creatorInboxId: String) async throws -> [Invite]
}

class InvitesRepository: InvitesRepositoryProtocol {
    let databaseReader: any DatabaseReader

    init(databaseReader: any DatabaseReader) {
        self.databaseReader = databaseReader
    }

    func fetchInvites(for creatorInboxId: String) async throws -> [Invite] {
        try await databaseReader.read { db in
            try DBInvite.filter(DBInvite.Columns.creatorInboxId == creatorInboxId)
                .fetchAll(db)
                .map { $0.hydrateInvite() }
        }
    }
}
