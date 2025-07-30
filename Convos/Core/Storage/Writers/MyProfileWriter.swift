import Foundation
import GRDB

protocol MyProfileWriterProtocol {
    func update(displayName: String) async throws
}

class MyProfileWriter: MyProfileWriterProtocol {
    private let inboxReadyValue: PublisherValue<InboxReadyResult>
    private let databaseWriter: any DatabaseWriter

    init(
        inboxReadyValue: PublisherValue<InboxReadyResult>,
        databaseWriter: any DatabaseWriter
    ) {
        self.inboxReadyValue = inboxReadyValue
        self.databaseWriter = databaseWriter
    }

    func update(displayName: String) async throws {
        guard let inboxReady = inboxReadyValue.value else {
            return
        }

        let displayName: String? = displayName.isEmpty ? nil : displayName
        let inboxId = inboxReady.client.inboxId
        try await databaseWriter.write { db in
            let member = Member(inboxId: inboxId)
            try member.save(db)
            let profile = try MemberProfile.fetchOne(db, key: inboxId) ?? .init(
                inboxId: inboxId,
                name: displayName,
                avatar: nil
            )
            try profile.with(name: displayName).save(db)
        }

        _ = try await inboxReady.apiClient.updateProfile(inboxId: inboxId, with: .init(name: displayName))
    }
}
