import Foundation

// MARK: - Response Types
struct FetchJwtResponse: Codable {
    let token: String
}

struct CreateSubOrganizationResponse: Codable {
    let subOrgId: String
    let walletAddress: String
}

// MARK: - Transport Types
enum AuthenticatorTransport: String, Codable {
    case ble = "AUTHENTICATOR_TRANSPORT_BLE"
    case transportInternal = "AUTHENTICATOR_TRANSPORT_INTERNAL"
    case nfc = "AUTHENTICATOR_TRANSPORT_NFC"
    case usb = "AUTHENTICATOR_TRANSPORT_USB"
    case hybrid = "AUTHENTICATOR_TRANSPORT_HYBRID"
}

// MARK: - Request Types
struct PasskeyAttestation: Codable {
    let credentialId: String
    let clientDataJson: String
    let attestationObject: String
    let transports: [AuthenticatorTransport]
}

struct Passkey: Codable {
    let challenge: String
    let attestation: PasskeyAttestation
}

final class ConvosAPIClient {
    internal let baseURL: URL
    private let keychainService: KeychainService<ConvosKeychainItem> = .init()
    internal let session: URLSession

    init(baseURL: URL) {
        self.baseURL = baseURL
        self.session = URLSession(configuration: .default)
    }

    // MARK: - Authentication

    func authenticate(xmtpInstallationId: String, xmtpId: String, xmtpSignature: String) async throws -> String {
        let url = baseURL.appendingPathComponent("v1/authenticate")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        // Set required headers
        request.setValue(xmtpInstallationId, forHTTPHeaderField: "X-XMTP-InstallationId")
        request.setValue(xmtpId, forHTTPHeaderField: "X-XMTP-InboxId")
        request.setValue("0x\(xmtpSignature)", forHTTPHeaderField: "X-XMTP-Signature")
        request.setValue(Secrets.FIREBASE_APP_CHECK_TOKEN, forHTTPHeaderField: "X-Firebase-AppCheck")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.authenticationFailed
        }

        struct AuthResponse: Codable {
            let token: String
        }

        let authResponse = try JSONDecoder().decode(AuthResponse.self, from: data)
        try keychainService.saveString(authResponse.token, for: .convosJwt)
        return authResponse.token
    }

    // MARK: - Users

    func getUser() async throws -> UserResponse {
        let request = try authenticatedRequest(for: "v1/users/me")
        let user: UserResponse = try await performRequest(request)
        return user
    }

    func createUser(_ requestBody: CreateUserRequest) async throws -> CreatedUserResponse {
        var request = try authenticatedRequest(for: "v1/users", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        Logger.info("Sending create user request with body: \(requestBody)")
        request.httpBody = try JSONEncoder().encode(requestBody)
        Logger.info("Creating user with json body: \(request.httpBody?.prettyPrintedJSONString ?? "")")
        return try await performRequest(request)
    }

    func checkUsername(_ username: String) async throws -> UsernameCheckResponse {
        let request = try authenticatedRequest(for: "v1/profiles/check/\(username)")
        let result: UsernameCheckResponse = try await performRequest(request)
        return result
    }

    // MARK: - Profiles

    func getProfile(inboxId: String) async throws -> ProfileResponse {
        let request = try authenticatedRequest(for: "v1/profiles/\(inboxId)")
        let profile: ProfileResponse = try await performRequest(request)
        return profile
    }

    func getProfiles(for inboxIds: [String]) async throws -> [ProfileResponse] {
        var request = try authenticatedRequest(for: "v1/profiles/batch", method: "POST")
        let body: [String: Any] = ["xmtpIds": inboxIds]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try await performRequest(request)
    }

    // MARK: - Private Helpers

    private func authenticatedRequest(for path: String, method: String = "GET") throws -> URLRequest {
        guard let jwt = try keychainService.retrieveString(.convosJwt) else {
            throw APIError.notAuthenticated
        }
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(jwt, forHTTPHeaderField: "X-Convos-AuthToken")
        return request
    }

    private func performRequest<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)

        Logger.info("Received response: \(data.prettyPrintedJSONString ?? "nil data")")

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            return try JSONDecoder().decode(T.self, from: data)
        case 401:
            throw APIError.notAuthenticated
        case 403:
            throw APIError.forbidden
        case 404:
            throw APIError.notFound
        default:
            throw APIError.serverError(nil)
        }
    }
}

// MARK: - Error Handling

enum APIError: Error {
    case authenticationFailed
    case notAuthenticated
    case forbidden
    case notFound
    case invalidResponse
    case serverError(Error?)
}
