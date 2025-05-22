import Foundation
import GRDB

extension Database {
    func currentUser() throws -> User? {
        guard let currentSession = try Session
            .including(required: Session.user)
            .including(required: Session.profile)
            .including(all: Session.identities)
            .asRequest(of: CurrentSessionDetails.self)
            .fetchOne(self) else {
            return nil
        }

        let user = User(
            id: currentSession.sessionUser.id,
            identities: currentSession.sessionIdentities,
            profile: currentSession.sessionProfile.hydrateProfile()
        )
        return user
    }
}
