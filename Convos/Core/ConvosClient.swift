import Combine
import Foundation
import GRDB

// Push notification types
public enum PushTokenType: String, Codable {
    case apns
    case expo
    case fcm
}

public struct InstallationInfo: Codable {
    public let identityId: String
    public let xmtpInstallationId: String

    public init(identityId: String, xmtpInstallationId: String) {
        self.identityId = identityId
        self.xmtpInstallationId = xmtpInstallationId
    }
}

public struct PushTokenRegistrationRequest: Codable {
    public let deviceId: String
    public let pushToken: String
    public let pushTokenType: PushTokenType
    public let apnsEnvironment: ApnsEnvironment
    public let installations: [InstallationInfo]

    public init(
        deviceId: String,
        pushToken: String,
        pushTokenType: PushTokenType = .apns,
        apnsEnvironment: ApnsEnvironment,
        installations: [InstallationInfo]
    ) {
        self.deviceId = deviceId
        self.pushToken = pushToken
        self.pushTokenType = pushTokenType
        self.apnsEnvironment = apnsEnvironment
        self.installations = installations
    }
}

public struct InstallationRegistrationResponse: Codable {
    public let status: String
    public let xmtpInstallationId: String
    public let validUntil: Int64?

    public init(status: String, xmtpInstallationId: String, validUntil: Int64? = nil) {
        self.status = status
        self.xmtpInstallationId = xmtpInstallationId
        self.validUntil = validUntil
    }
}

public struct PushTokenRegistrationResponse: Codable {
    public let responses: [InstallationRegistrationResponse]

    public init(responses: [InstallationRegistrationResponse]) {
        self.responses = responses
    }
}

final class ConvosClient {
    private let authService: any LocalAuthServiceProtocol
    private let sessionManager: any SessionManagerProtocol
    private let databaseManager: any DatabaseManagerProtocol
    private let environment: AppEnvironment

    private var _apiClient: (any ConvosAPIClientProtocol)?

    private func createAPIClient() async throws -> any ConvosAPIClientProtocol {
        // Get the first available messaging service and wait for it to be ready
        guard let firstInbox = try sessionManager.inboxesRepository.allInboxes().first else {
            throw APIError.notAuthenticated
        }
        let firstInboxId = firstInbox.inboxId

        let messagingService = sessionManager.messagingService(for: firstInboxId)
        guard let messagingService = messagingService as? MessagingService else {
            throw APIError.notAuthenticated
        }

        // Wait for the inbox to be ready to get the XMTP client
        var inboxReadyIterator = messagingService.inboxReadyPublisher.values.makeAsyncIterator()
        guard let inboxReady = await inboxReadyIterator.next() else {
            throw APIError.notAuthenticated
        }

        return ConvosAPIClientFactory.authenticatedClient(
            client: inboxReady.client,
            environment: environment
        )
    }

    private func apiClient() async throws -> any ConvosAPIClientProtocol {
        if let existingClient = _apiClient {
            return existingClient
        }
        let newClient = try await createAPIClient()
        _apiClient = newClient
        return newClient
    }

    var databaseWriter: any DatabaseWriter {
        databaseManager.dbWriter
    }

    var databaseReader: any DatabaseReader {
        databaseManager.dbReader
    }

    var session: any SessionManagerProtocol {
        sessionManager
    }

    static func testClient(
        authService: any LocalAuthServiceProtocol = SecureEnclaveAuthService()
    ) -> ConvosClient {
        let environment = AppEnvironment.tests
        let databaseManager = MockDatabaseManager.shared
        let sessionManager = SessionManager(
            authService: authService,
            databaseWriter: databaseManager.dbWriter,
            databaseReader: databaseManager.dbReader,
            environment: environment
        )
        return .init(authService: authService,
                     sessionManager: sessionManager,
                     databaseManager: databaseManager,
                     environment: environment)
    }

    static func mock() -> ConvosClient {
        let authService = MockAuthService()
        let databaseManager = MockDatabaseManager.previews
        let sessionManager = MockInboxesService()
        let environment = AppEnvironment.tests
        return .init(authService: authService,
                     sessionManager: sessionManager,
                     databaseManager: databaseManager,
                     environment: environment)
    }

    internal init(authService: any LocalAuthServiceProtocol,
                  sessionManager: any SessionManagerProtocol,
                  databaseManager: any DatabaseManagerProtocol,
                  environment: AppEnvironment) {
        self.authService = authService
        self.sessionManager = sessionManager
        self.databaseManager = databaseManager
        self.environment = environment
    }

    var authState: AnyPublisher<AuthServiceState, Never> {
        sessionManager.authState
    }

    func prepare() throws {
        try sessionManager.prepare()
    }

    // MARK: - Push Notifications

    func registerPushToken(_ request: PushTokenRegistrationRequest) async throws -> PushTokenRegistrationResponse {
        let client = try await apiClient()
        return try await client.registerPushToken(request)
    }
}
