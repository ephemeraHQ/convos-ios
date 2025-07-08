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

protocol ConvosAPIClientProtocol {
    var xmtpClientProvider: (any XMTPClientProvider)? { get }
    func setXMTPClientProvider(_ provider: (any XMTPClientProvider)?)
    func authenticate(xmtpInstallationId: String,
                      xmtpId: String,
                      xmtpSignature: String) async throws -> String

    func getUser() async throws -> ConvosAPI.UserResponse
    func createUser(_ requestBody: ConvosAPI.CreateUserRequest) async throws -> ConvosAPI.CreatedUserResponse
    func checkUsername(_ username: String) async throws -> ConvosAPI.UsernameCheckResponse

    func getProfile(inboxId: String) async throws -> ConvosAPI.ProfileResponse
    func getProfiles(for inboxIds: [String]) async throws -> ConvosAPI.BatchProfilesResponse
    func getProfiles(matching query: String) async throws -> [ConvosAPI.ProfileResponse]

    func uploadAttachment(data: Data, filename: String) async throws -> String
}

final class ConvosAPIClient: ConvosAPIClientProtocol {
    internal let baseURL: URL
    private let keychainService: KeychainService<ConvosKeychainItem> = .init()
    internal let session: URLSession
    private(set) var xmtpClientProvider: (any XMTPClientProvider)?

    private let maxRetryCount: Int = 3

    static var shared: ConvosAPIClient = {
        guard let apiBaseURL = URL(string: Secrets.CONVOS_API_BASE_URL) else {
            fatalError("Failed constructing API base URL")
        }
        return ConvosAPIClient(baseURL: apiBaseURL)
    }()

    func setXMTPClientProvider(_ provider: (any XMTPClientProvider)?) {
        xmtpClientProvider = provider
    }

    private init(baseURL: URL) {
        self.baseURL = baseURL
        self.session = URLSession(configuration: .default)
    }

    private func reAuthenticate() async throws -> String {
        guard let client = xmtpClientProvider else {
            throw APIError.notAuthenticated
        }

        let installationId = client.installationId
        let xmtpId = client.inboxId
        let firebaseAppCheckToken = Secrets.FIREBASE_APP_CHECK_TOKEN
        let signatureData = try client.signWithInstallationKey(message: firebaseAppCheckToken)
        let signature = signatureData.hexEncodedString()

        return try await authenticate(
            xmtpInstallationId: installationId,
            xmtpId: xmtpId,
            xmtpSignature: signature
        )
    }

    // MARK: - Authentication

    func authenticate(xmtpInstallationId: String,
                      xmtpId: String,
                      xmtpSignature: String) async throws -> String {
        let url = baseURL.appendingPathComponent("v1/authenticate")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

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

    func getUser() async throws -> ConvosAPI.UserResponse {
        let request = try authenticatedRequest(for: "v1/users/me")
        let user: ConvosAPI.UserResponse = try await performRequest(request)
        return user
    }

    func createUser(_ requestBody: ConvosAPI.CreateUserRequest) async throws -> ConvosAPI.CreatedUserResponse {
        var request = try authenticatedRequest(for: "v1/users", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        Logger.info("Sending create user request with body: \(requestBody)")
        request.httpBody = try JSONEncoder().encode(requestBody)
        Logger.info("Creating user with json body: \(request.httpBody?.prettyPrintedJSONString ?? "")")
        return try await performRequest(request)
    }

    func checkUsername(_ username: String) async throws -> ConvosAPI.UsernameCheckResponse {
        let request = try authenticatedRequest(for: "v1/profiles/check/\(username)")
        let result: ConvosAPI.UsernameCheckResponse = try await performRequest(request)
        return result
    }

    // MARK: - Profiles

    func getProfile(inboxId: String) async throws -> ConvosAPI.ProfileResponse {
        let request = try authenticatedRequest(for: "v1/profiles/\(inboxId)")
        let profile: ConvosAPI.ProfileResponse = try await performRequest(request)
        return profile
    }

    func getProfiles(for inboxIds: [String]) async throws -> ConvosAPI.BatchProfilesResponse {
        var request = try authenticatedRequest(for: "v1/profiles/batch", method: "POST")
        let body: [String: Any] = ["xmtpIds": inboxIds]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try await performRequest(request)
    }

    func getProfiles(matching query: String) async throws -> [ConvosAPI.ProfileResponse] {
        let request = try authenticatedRequest(
            for: "v1/profiles/search",
            queryParameters: ["query": query]
        )
        return try await performRequest(request)
    }

    // MARK: - Private Helpers

    private func authenticatedRequest(
        for path: String,
        method: String = "GET",
        queryParameters: [String: String]? = nil
    ) throws -> URLRequest {
        guard let jwt = try keychainService.retrieveString(.convosJwt) else {
            throw APIError.notAuthenticated
        }

        var urlComponents = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if let queryParameters = queryParameters {
            urlComponents?.queryItems = queryParameters.map { URLQueryItem(name: $0.key, value: $0.value) }
        }

        guard let url = urlComponents?.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(jwt, forHTTPHeaderField: "X-Convos-AuthToken")
        return request
    }

    private func performRequest<T: Decodable>(_ request: URLRequest, retryCount: Int = 0) async throws -> T {
        let (data, response) = try await session.data(for: request)

        Logger.info("Received response: \(data.prettyPrintedJSONString ?? "nil data")")

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            return try JSONDecoder().decode(T.self, from: data)
        case 401:
            // Check if we've exceeded max retries
            guard retryCount < maxRetryCount else {
                Logger.error("Max retry count (\(maxRetryCount)) exceeded for request")
                throw APIError.notAuthenticated
            }

            // Try to re-authenticate and retry the request
            do {
                Logger.info("Attempting re-authentication (attempt \(retryCount + 1) of \(maxRetryCount))")
                _ = try await reAuthenticate()
                // Create a new request with the fresh token
                var newRequest = request
                if let jwt = try keychainService.retrieveString(.convosJwt) {
                    newRequest.setValue(jwt, forHTTPHeaderField: "X-Convos-AuthToken")
                }
                // Retry the request with incremented retry count
                return try await performRequest(newRequest, retryCount: retryCount + 1)
            } catch {
                Logger.error("Re-authentication failed: \(error.localizedDescription)")
                throw APIError.notAuthenticated
            }
        case 403:
            throw APIError.forbidden
        case 404:
            throw APIError.notFound
        default:
            throw APIError.serverError(nil)
        }
    }

    func uploadAttachment(data: Data, filename: String) async throws -> String {
        Logger.info("Starting attachment upload process for file: \(filename)")
        Logger.info("File data size: \(data.count) bytes")

        // Step 1: Get presigned URL from Convos API
        let presignedRequest = try authenticatedRequest(
            for: "v1/attachments/presigned",
            method: "GET",
            queryParameters: ["contentType": "image/jpeg"]
        )

        Logger.info("Getting presigned URL from: \(presignedRequest.url?.absoluteString ?? "nil")")

        struct PresignedResponse: Codable {
            let url: String
        }

        let presignedResponse: PresignedResponse = try await performRequest(presignedRequest)
        Logger.info("Received presigned URL: \(presignedResponse.url)")

        // Step 2: Upload directly to S3 using presigned URL
        guard let s3URL = URL(string: presignedResponse.url) else {
            Logger.error("Invalid presigned URL: \(presignedResponse.url)")
            throw APIError.invalidURL
        }

        var s3Request = URLRequest(url: s3URL)
        s3Request.httpMethod = "PUT"
        s3Request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        s3Request.setValue("public-read", forHTTPHeaderField: "x-amz-acl")
        s3Request.httpBody = data

        Logger.info("Uploading to S3: \(s3URL.absoluteString)")
        Logger.info("S3 upload data size: \(data.count) bytes")
        Logger.info("S3 request headers: \(s3Request.allHTTPHeaderFields ?? [:])")

        let (s3Data, s3Response) = try await URLSession.shared.data(for: s3Request)

        guard let s3HttpResponse = s3Response as? HTTPURLResponse else {
            Logger.error("Invalid S3 response type")
            throw APIError.invalidResponse
        }

        Logger.info("S3 response status: \(s3HttpResponse.statusCode)")
        Logger.info("S3 response headers: \(s3HttpResponse.allHeaderFields)")

        guard s3HttpResponse.statusCode == 200 else {
            Logger.error("S3 upload failed with status: \(s3HttpResponse.statusCode)")
            Logger.error("S3 error response: \(String(data: s3Data, encoding: .utf8) ?? "nil")")
            throw APIError.serverError(nil)
        }

        // Step 3: Extract public URL (remove query parameters from presigned URL)
        guard let urlComponents = URLComponents(string: presignedResponse.url) else {
            Logger.error("Failed to parse presigned URL components")
            throw APIError.invalidURL
        }

        guard let scheme = urlComponents.scheme, let host = urlComponents.host else {
            Logger.error("Failed to extract scheme or host from presigned URL")
            throw APIError.invalidURL
        }
        let publicURL = "\(scheme)://\(host)\(urlComponents.path)"
        Logger.info("Successfully uploaded to S3, public URL: \(publicURL)")

        return publicURL
    }
}

// MARK: - Error Handling

enum APIError: Error {
    case invalidURL
    case authenticationFailed
    case notAuthenticated
    case forbidden
    case notFound
    case invalidResponse
    case invalidRequest
    case serverError(Error?)
}
