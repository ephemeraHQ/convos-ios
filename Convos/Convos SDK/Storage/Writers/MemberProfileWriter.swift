import Foundation
import GRDB
import XMTPiOS

protocol MemberProfileWriterProtocol {
    func store(profiles: [ConvosAPI.ProfileResponse]) async throws
}

class MemberProfileWriter: MemberProfileWriterProtocol {
    private let databaseWriter: any DatabaseWriter

    init(databaseWriter: any DatabaseWriter) {
        self.databaseWriter = databaseWriter
    }

    func store(profiles: [ConvosAPI.ProfileResponse]) async throws {
        let memberProfiles: [MemberProfile] = profiles.map { profile in
                .init(inboxId: profile.xmtpId,
                      name: profile.name,
                      username: profile.username,
                      avatar: profile.avatar)
        }
        try await databaseWriter.write { db in
            for memberProfile in memberProfiles {
                try memberProfile.save(db)
            }
        }
    }
}
