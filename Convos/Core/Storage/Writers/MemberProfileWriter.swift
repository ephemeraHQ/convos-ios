import Foundation
import GRDB
import XMTPiOS

protocol MemberProfileWriterProtocol {
    func store(memberProfiles: [MemberProfile]) async throws
    func store(profiles: [ConvosAPI.ProfileResponse]) async throws
}

class MemberProfileWriter: MemberProfileWriterProtocol {
    private let databaseWriter: any DatabaseWriter

    init(databaseWriter: any DatabaseWriter) {
        self.databaseWriter = databaseWriter
    }

    func store(memberProfiles: [MemberProfile]) async throws {
        try await databaseWriter.write { db in
            for memberProfile in memberProfiles {
                let member = Member(inboxId: memberProfile.inboxId)
                try member.save(db)
                try memberProfile.save(db)
            }
        }
    }

    func store(profiles: [ConvosAPI.ProfileResponse]) async throws {
        let memberProfiles: [MemberProfile] = profiles.map { profile in
                .init(inboxId: profile.xmtpId,
                      name: profile.name,
                      avatar: profile.avatar)
        }
        try await store(memberProfiles: memberProfiles)
    }
}
