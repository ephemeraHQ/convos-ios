import Foundation

public protocol ConvosAPIBaseProtocol {
    // turnkey specific
    func createSubOrganization(
        ephemeralPublicKey: String,
        passkey: ConvosAPI.Passkey
    ) async throws -> ConvosAPI.CreateSubOrganizationResponse

    func request(for path: String,
                 method: String,
                 queryParameters: [String: String]?) throws -> URLRequest
}

protocol ConvosAPIClientFactoryType {
    static func client(environment: AppEnvironment) -> any ConvosAPIBaseProtocol
    static func authenticatedClient(
        client: any XMTPClientProvider,
        environment: AppEnvironment
    ) -> any ConvosAPIClientProtocol
}

enum ConvosAPIClientFactory: ConvosAPIClientFactoryType {
    static func client(environment: AppEnvironment) -> any ConvosAPIBaseProtocol {
        BaseConvosAPIClient(environment: environment)
    }

    static func authenticatedClient(
        client: any XMTPClientProvider,
        environment: AppEnvironment
    ) -> any ConvosAPIClientProtocol {
        ConvosAPIClient(client: client, environment: environment)
    }
}

public protocol ConvosAPIClientProtocol: ConvosAPIBaseProtocol, AnyObject {
    var identifier: String { get }

    func authenticate(inboxId: String,
                      appCheckToken: String,
                      retryCount: Int) async throws -> String

    func checkAuth() async throws

    func uploadAttachment(
        data: Data,
        filename: String,
        contentType: String,
        acl: String
    ) async throws -> String
    func uploadAttachmentAndExecute(
        data: Data,
        filename: String,
        afterUpload: @escaping (String) async throws -> Void
    ) async throws -> String

    // Push notifications
    func registerDevice(deviceId: String, pushToken: String?) async throws
    func subscribeToTopics(deviceId: String, clientId: String, topics: [String]) async throws
    func unsubscribeFromTopics(clientId: String, topics: [String]) async throws
    func unregisterInstallation(clientId: String) async throws

    func overrideJWTToken(_ token: String)
}

internal class BaseConvosAPIClient: ConvosAPIBaseProtocol {
    internal let baseURL: URL
    internal let session: URLSession
    internal let environment: AppEnvironment

    fileprivate init(environment: AppEnvironment) {
        guard let apiBaseURL = URL(string: environment.apiBaseURL) else {
            fatalError("Failed constructing API base URL")
        }
        self.baseURL = apiBaseURL
        self.session = URLSession(configuration: .default)
        self.environment = environment
    }

    func createSubOrganization(
        ephemeralPublicKey: String,
        passkey: ConvosAPI.Passkey
    ) async throws -> ConvosAPI.CreateSubOrganizationResponse {
        let url = baseURL.appendingPathComponent("v1/wallets")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody: [String: Any] = [
            "ephemeralPublicKey": ephemeralPublicKey,
            "challenge": passkey.challenge,
            "attestation": [
                "credentialId": passkey.attestation.credentialId,
                "clientDataJson": passkey.attestation.clientDataJson,
                "attestationObject": passkey.attestation.attestationObject,
                "transports": passkey.attestation.transports.map { $0.rawValue }
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
                throw APIError.authenticationFailed
            }

            let result = try JSONDecoder().decode(ConvosAPI.CreateSubOrganizationResponse.self, from: data)
            return result
        } catch {
            throw APIError.serverError(error.localizedDescription)
        }
    }

    func request(for path: String,
                 method: String = "GET",
                 queryParameters: [String: String]? = nil) throws -> URLRequest {
        var urlComponents = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if let queryParameters = queryParameters {
            urlComponents?.queryItems = queryParameters.map { URLQueryItem(name: $0.key, value: $0.value) }
        }

        guard let url = urlComponents?.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        return request
    }

    private func performRequest<T: Decodable>(_ request: URLRequest, retryCount: Int = 0) async throws -> T {
        let (data, response) = try await session.data(for: request)

        Logger.info("\(request.url?.path(percentEncoded: false) ?? "nil") received response: \(data.prettyPrintedJSONString ?? "nil data")")

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(T.self, from: data)
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

final class ConvosAPIClient: BaseConvosAPIClient, ConvosAPIClientProtocol {
    private let client: any XMTPClientProvider
    private let keychainService: KeychainService<ConvosJWTKeychainItem> = .init()

    private var _overrideJWTToken: String?
    private let tokenAccessQueue: DispatchQueue = DispatchQueue(label: "org.convos.api.tokenAccess")

    private let maxRetryCount: Int = 3

    var identifier: String {
        "\(client.inboxId)-\(client.installationId)"
    }

    fileprivate init(
        client: any XMTPClientProvider,
        environment: AppEnvironment
    ) {
        self.client = client
        super.init(environment: environment)
    }

    private func reAuthenticate() async throws -> String {
        let inboxId = client.inboxId
        let firebaseAppCheckToken = try await FirebaseHelperCore.getAppCheckToken()

        return try await authenticate(
            inboxId: inboxId,
            appCheckToken: firebaseAppCheckToken,
            retryCount: 0
        )
    }

    // MARK: - Authentication

    /// Authenticates with the backend to obtain a JWT token
    /// - Parameters:
    ///   - inboxId: Used to store the JWT token in keychain (not sent to backend)
    ///   - appCheckToken: Firebase AppCheck token for authentication
    ///   - retryCount: Number of retry attempts (for rate limiting)
    /// - Returns: JWT token string
    func authenticate(inboxId: String,
                      appCheckToken: String,
                      retryCount: Int = 0) async throws -> String {
        let url = baseURL.appendingPathComponent("v2/auth/token")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        request.setValue(appCheckToken, forHTTPHeaderField: "X-Firebase-AppCheck")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        struct AuthRequest: Encodable {
            let deviceId: String
        }

        let deviceId = DeviceInfo.deviceIdentifier
        let requestBody = AuthRequest(deviceId: deviceId)
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.authenticationFailed
        }

        // Handle bad request
        if httpResponse.statusCode == 400 {
            throw APIError.badRequest(parseErrorMessage(from: data))
        }

        // Handle auth rate limiting
        if httpResponse.statusCode == 429 {
            guard retryCount < maxRetryCount else {
                throw APIError.rateLimitExceeded
            }
            // Use exponential backoff for rate limit retries
            let delay = TimeInterval.calculateExponentialBackoff(for: retryCount)
            Logger.info("Auth rate limited - retrying in \(delay)s (attempt \(retryCount + 1) of \(maxRetryCount))")

            // Sleep and then retry
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            return try await authenticate(inboxId: inboxId,
                                          appCheckToken: appCheckToken,
                                          retryCount: retryCount + 1)
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = parseErrorMessage(from: data)
            Logger.error("Authentication failed with status \(httpResponse.statusCode): \(errorMessage ?? "unknown error")")
            throw APIError.authenticationFailed
        }

        struct AuthResponse: Codable {
            let token: String
        }

        let authResponse = try JSONDecoder().decode(AuthResponse.self, from: data)
        try keychainService.saveString(authResponse.token, for: .init(inboxId: inboxId))
        Logger.info("Successfully authenticated and stored JWT token")
        return authResponse.token
    }

    func checkAuth() async throws {
        let request = try authenticatedRequest(for: "v2/auth-check")
        let _: ConvosAPI.AuthCheckResponse = try await performRequest(request)
    }

    /// Sets a JWT token in RAM for use in notification service extension.
    /// This token will be prioritized over the keychain-stored JWT for authenticated requests.
    /// - Parameter token: The JWT token to use for authentication
    func overrideJWTToken(_ token: String) {
        tokenAccessQueue.sync {
            _overrideJWTToken = token
        }
    }

    // MARK: - Private Helpers

    private func authenticatedRequest(
        for path: String,
        method: String = "GET",
        queryParameters: [String: String]? = nil
    ) throws -> URLRequest {
        var request = try request(for: path, method: method, queryParameters: queryParameters)

        // Prioritize override JWT token (from notification payload) over keychain JWT
        // Capture the override token in a synchronized block to avoid race conditions
        let overrideToken = tokenAccessQueue.sync { _overrideJWTToken }

        if let overridenJWT = overrideToken {
            request.setValue(overridenJWT, forHTTPHeaderField: "X-Convos-AuthToken")
        } else if let keychainJWT = try? keychainService.retrieveString(.init(inboxId: client.inboxId)) {
            request.setValue(keychainJWT, forHTTPHeaderField: "X-Convos-AuthToken")
        }
        // If no JWT, send request anyway - server will respond 401 and performRequest() will handle reauth

        return request
    }

    private func performRequest<T: Decodable>(_ request: URLRequest, retryCount: Int = 0) async throws -> T {
        do {
            let (data, response) = try await session.data(for: request)

            Logger.info("\(request.url?.path(percentEncoded: false) ?? "nil") received response: \(data.prettyPrintedJSONString ?? "nil data")")

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }

            switch httpResponse.statusCode {
            case 200...203, 206...299:
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                return try decoder.decode(T.self, from: data)
            case 204, 205, 304:
                // Handle no content responses
                if T.self == Void.self {
                    return unsafeBitCast((), to: T.self)
                } else if let emptyDict = [:] as? T {
                    return emptyDict
                } else if let emptyArray = [] as? T {
                    return emptyArray
                } else {
                    // For other types, try to decode empty data or throw appropriate error
                    throw APIError.invalidResponse
                }
            case 400:
                // Parse error message from response if available
                let errorMessage: String?
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let message = json["message"] as? String {
                    errorMessage = message
                } else {
                    errorMessage = String(data: data, encoding: .utf8)
                }
                throw APIError.badRequest(errorMessage)
            case 401:
                // If using override JWT token (notification service extension), don't attempt re-auth
                // since app attest is not available in notification service extension
                let hasOverrideToken = tokenAccessQueue.sync { _overrideJWTToken != nil }
                guard !hasOverrideToken else {
                    Logger.error("Authentication failed with override JWT token - cannot re-authenticate in notification service extension")
                    throw APIError.notAuthenticated
                }

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
                    if let jwt = try keychainService.retrieveString(.init(inboxId: client.inboxId)) {
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
                let errorMessage = String(data: data, encoding: .utf8)
                throw APIError.serverError(errorMessage)
            }
        } catch {
            throw error
        }
    }

    func uploadAttachment(
        data: Data,
        filename: String,
        contentType: String = "image/jpeg",
        acl: String = "public-read"
    ) async throws -> String {
        Logger.info("Starting attachment upload process for file: \(filename)")
        Logger.info("File data size: \(data.count) bytes")

        // Step 1: Get presigned URL from Convos API
        let presignedRequest = try authenticatedRequest(
            for: "v1/attachments/presigned",
            method: "GET",
            queryParameters: ["contentType": contentType, "filename": filename]
        )

        Logger.info("Getting presigned URL from: \(presignedRequest.url?.absoluteString ?? "nil")")

        struct PresignedResponse: Codable {
            let url: String
        }

        let presignedResponse: PresignedResponse = try await performRequest(presignedRequest)
        Logger.info("Received presigned URL: \(presignedResponse.url)")

        // Step 2: Extract public URL BEFORE uploading (we already know what it will be!)
        guard let urlComponents = URLComponents(string: presignedResponse.url) else {
            Logger.error("Failed to parse presigned URL components")
            throw APIError.invalidURL
        }

        guard let scheme = urlComponents.scheme, let host = urlComponents.host else {
            Logger.error("Failed to extract scheme or host from presigned URL")
            throw APIError.invalidURL
        }
        let publicURL = "\(scheme)://\(host)\(urlComponents.path)"
        Logger.info("Final public URL will be: \(publicURL)")

        // Step 3: Upload directly to S3 using presigned URL
        guard let s3URL = URL(string: presignedResponse.url) else {
            Logger.error("Invalid presigned URL: \(presignedResponse.url)")
            throw APIError.invalidURL
        }

        var s3Request = URLRequest(url: s3URL)
        s3Request.httpMethod = "PUT"
        s3Request.setValue(contentType, forHTTPHeaderField: "Content-Type")
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

        Logger.info("Successfully uploaded to S3, public URL: \(publicURL)")
        return publicURL
    }

    func uploadAttachmentAndExecute(
        data: Data,
        filename: String,
        afterUpload: @escaping (String) async throws -> Void
    ) async throws -> String {
        Logger.info("Starting chained upload and execute process for file: \(filename)")

        // Step 1: Upload the attachment and get the URL
        let uploadedURL = try await uploadAttachment(
            data: data,
            filename: filename,
            contentType: "image/jpeg",
            acl: "public-read"
        )
        Logger.info("Upload completed successfully, URL: \(uploadedURL)")

        // Step 2: Execute the provided closure with the uploaded URL
        Logger.info("Executing post-upload action with URL: \(uploadedURL)")
        try await afterUpload(uploadedURL)
        Logger.info("Post-upload action completed successfully")

        return uploadedURL
    }

    // MARK: - Notifications Registration & Subscriptions

    /// Supports optional push token (for early registration)
    func registerDevice(deviceId: String, pushToken: String?) async throws {
        var request = try authenticatedRequest(for: "v2/notifications/register", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        struct RegisterDeviceRequest: Encodable {
            let deviceId: String
            let pushToken: String?
            let pushTokenType: String?
            let apnsEnv: String?
        }

        let apnsEnv: String?
        let pushTokenType: String?
        if pushToken != nil {
            apnsEnv = environment.apnsEnvironment == .sandbox ? "sandbox" : "production"
            pushTokenType = "apns"
            Logger.info("Registering device with push token and APNS environment: \(apnsEnv ?? "nil") (raw enum: \(environment.apnsEnvironment))")
        } else {
            apnsEnv = nil
            pushTokenType = nil
            Logger.info("Registering device without push token (early registration)")
        }

        let body = RegisterDeviceRequest(
            deviceId: deviceId,
            pushToken: pushToken,
            pushTokenType: pushTokenType,
            apnsEnv: apnsEnv
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200...299 ~= http.statusCode else {
            throw APIError.serverError("Failed v2/notifications/register: \((response as? HTTPURLResponse)?.statusCode.description ?? "?")")
        }
    }

    func subscribeToTopics(deviceId: String, clientId: String, topics: [String]) async throws {
        var request = try authenticatedRequest(for: "v2/notifications/subscribe", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        struct HmacKey: Encodable {
            let thirtyDayPeriodsSinceEpoch: Int
            let key: String
        }

        struct TopicSubscription: Encodable {
            let topic: String
            let hmacKeys: [HmacKey]
        }

        struct SubscribeRequest: Encodable {
            let deviceId: String
            let clientId: String
            let topics: [TopicSubscription]
        }

        let topicSubscriptions: [TopicSubscription] = topics.map { topic in
            TopicSubscription(topic: topic, hmacKeys: [])
        }

        request.httpBody = try JSONEncoder().encode(SubscribeRequest(
            deviceId: deviceId,
            clientId: clientId,
            topics: topicSubscriptions
        ))

        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200...299 ~= http.statusCode else {
            throw APIError.serverError("Failed v2/notifications/subscribe: \((response as? HTTPURLResponse)?.statusCode.description ?? "?")")
        }
    }

    func unsubscribeFromTopics(clientId: String, topics: [String]) async throws {
        var request = try authenticatedRequest(for: "v2/notifications/unsubscribe", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        struct UnsubscribeRequest: Encodable {
            let clientId: String
            let topics: [String]
        }

        request.httpBody = try JSONEncoder().encode(UnsubscribeRequest(clientId: clientId, topics: topics))
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200...299 ~= http.statusCode else {
            throw APIError.serverError("Failed v2/notifications/unsubscribe: \((response as? HTTPURLResponse)?.statusCode.description ?? "?")")
        }
    }

    func unregisterInstallation(clientId: String) async throws {
        let path = "v2/notifications/unregister/\(clientId)"
        let request = try authenticatedRequest(for: path, method: "DELETE")
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200...299 ~= http.statusCode else {
            throw APIError.serverError("Failed DELETE v2/notifications/unregister: \((response as? HTTPURLResponse)?.statusCode.description ?? "?")")
        }
    }

    // MARK: - Helper Methods

    private func parseErrorMessage(from data: Data) -> String? {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = json["message"] as? String {
            return message
        }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Error Handling

enum APIError: Error {
    case invalidURL
    case authenticationFailed
    case notAuthenticated
    case badRequest(String?)
    case forbidden
    case notFound
    case invalidResponse
    case invalidRequest
    case serverError(String?)
    case rateLimitExceeded
}

extension TimeInterval {
    public static func calculateExponentialBackoff(for retryCount: Int) -> TimeInterval {
        guard retryCount >= 0 else { return 0.0 }
        let baseDelay: TimeInterval = 1.0
        let exponentialDelay = baseDelay * pow(2.0, Double(retryCount))
        let jitter = Double.random(in: 0...0.1) * exponentialDelay
        return min(exponentialDelay + jitter, 30.0) // Cap at 30 seconds
    }
}
