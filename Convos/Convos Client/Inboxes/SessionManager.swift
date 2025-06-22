import Combine
import Foundation
import GRDB

enum SessionManagerError: Error {
    case noSuchMessagingService(String)
}

class SessionManager: SessionManagerProtocol {
    let inboxesRepository: any InboxesRepositoryProtocol

    private let databaseWriter: any DatabaseWriter
    private let databaseReader: any DatabaseReader
    private var cancellables: Set<AnyCancellable> = []
    private let authService: any AuthServiceProtocol
    private let environment: AppEnvironment

    init(authService: any AuthServiceProtocol,
         databaseWriter: any DatabaseWriter,
         databaseReader: any DatabaseReader,
         environment: AppEnvironment) {
        self.databaseWriter = databaseWriter
        self.databaseReader = databaseReader
        self.inboxesRepository = InboxesRepository(databaseReader: databaseReader)
        self.authService = authService
        self.environment = environment

        authService.authStatePublisher.sink { [weak self] authState in
            Logger.info("Auth state changed: \(authState)")
            guard let self = self else { return }
            switch authState {
            case .authorized(let authResult):
                break
            case .registered(let registeredResult):
                break
            case .unauthorized:
                Logger.info("Stopping from auth state changing to unauthorized")
            default:
                break
            }
        }
        .store(in: &cancellables)
    }

    // MARK: Messaging

    func messagingService(for inboxId: String) throws -> any MessagingServiceProtocol {
        MockMessagingService()
    }

    // MARK: Displaying All Conversations

    func conversationsRepository(for consent: [Consent]) -> any ConversationsRepositoryProtocol {
        ConversationsRepository(dbReader: databaseReader, consent: consent)
    }

    func conversationsCountRepo(for consent: [Consent]) -> any ConversationsCountRepositoryProtocol {
        ConversationsCountRepository(databaseReader: databaseReader, consent: consent)
    }
}
