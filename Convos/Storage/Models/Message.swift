import Foundation
import GRDB

struct Message: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable {
    enum Kind: Hashable, Codable {
        case text(String)
        case attachment(URL)
    }

    enum Status: Hashable, Codable {
        case unpublished, published
    }

    enum Source: Hashable, Codable {
        case incoming, outgoing

        var isIncoming: Bool {
            self == .incoming
        }
    }

    let id: String
    let userId: String
    let userProfile: Profile
    let date: Date
    let kind: Kind
    let source: Source
    let status: Status
}
