import Foundation
import GRDB

extension Database {
    func currentSession() throws -> CurrentSession? {
        guard let currentSession = try Session
            .including(all: Session.inboxes)
            .asRequest(of: CurrentSessionDetails.self)
            .fetchOne(self) else {
            return nil
        }

        return .init(inboxes: [])
    }
}
