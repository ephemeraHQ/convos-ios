import Foundation
import GRDB

struct DBUser: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable {
    static let databaseTableName: String = "user"
    let id: String
}

struct User: Codable, Identifiable, Hashable {
    let id: String
    let identities: [Identity]
    let profile: Profile
}

struct Identity: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable {
    let id: String
    let userId: String
    let walletAddress: String
    let xmtpId: String?
}

struct Session: Codable, FetchableRecord, PersistableRecord, TableRecord, Identifiable {
    static let databaseTableName: String = "session"
    var id: Int64 = 1
    var currentUserId: String
}
