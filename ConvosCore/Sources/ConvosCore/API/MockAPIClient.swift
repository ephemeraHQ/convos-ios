import Foundation

class MockAPIClientFactory: ConvosAPIClientFactoryType {
    static func client(environment: AppEnvironment) -> any ConvosAPIBaseProtocol {
        MockBaseAPIClient()
    }

    static func authenticatedClient(
        client: any XMTPClientProvider,
        environment: AppEnvironment
    ) -> any ConvosAPIClientProtocol {
        MockAPIClient(client: client)
    }
}

enum MockAPIError: Error {
    case invalidURL
}

class MockBaseAPIClient: ConvosAPIBaseProtocol {
    func createSubOrganization(
        ephemeralPublicKey: String,
        passkey: ConvosAPI.Passkey
    ) async throws -> ConvosAPI.CreateSubOrganizationResponse {
        .init(subOrgId: UUID().uuidString, walletAddress: UUID().uuidString)
    }

    func request(for path: String, method: String, queryParameters: [String: String]?) throws -> URLRequest {
        guard let url = URL(string: "http://example.com") else {
            throw MockAPIError.invalidURL
        }
        return URLRequest(url: url)
    }

    func registerDevice(deviceId: String, pushToken: String?) async throws {
        // Mock implementation - no-op
    }
}

class MockAPIClient: MockBaseAPIClient, ConvosAPIClientProtocol {
    var identifier: String {
        "\(client.inboxId)\(client.installationId)"
    }

    let client: any XMTPClientProvider

    init(client: any XMTPClientProvider) {
        self.client = client
        super.init()
    }

    func authenticate(appCheckToken: String, retryCount: Int = 0) async throws -> String {
        return "mock-jwt-token"
    }

    func checkAuth() async throws {
        // Mock implementation - always succeeds
    }

    func uploadAttachment(
        data: Data,
        filename: String,
        contentType: String,
        acl: String
    ) async throws -> String {
        return "https://mock-api.example.com/uploads/\(filename)"
    }

    func uploadAttachmentAndExecute(
        data: Data,
        filename: String,
        afterUpload: @escaping (String) async throws -> Void
    ) async throws -> String {
        let uploadedURL = "https://mock-api.example.com/uploads/\(filename)"
        try await afterUpload(uploadedURL)
        return uploadedURL
    }

    // MARK: - Notifications mocks

    func subscribeToTopics(deviceId: String, clientId: String, topics: [String]) async throws {
        // no-op in mock
    }

    func unsubscribeFromTopics(clientId: String, topics: [String]) async throws {
        // no-op in mock
    }

    func unregisterInstallation(clientId: String) async throws {
        // no-op in mock
    }

    func overrideJWTToken(_ token: String) {
        // no-op in mock
    }
}
