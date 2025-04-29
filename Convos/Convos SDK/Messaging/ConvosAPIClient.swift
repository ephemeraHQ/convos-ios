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
    private let baseURL: URL
    private let keychainService: KeychainService<ConvosKeychainItem> = .init()
    private let session: URLSession

    init(baseURL: URL) {
        self.baseURL = baseURL
        self.session = URLSession(configuration: .default)
    }

    // MARK: - Authentication

    func createSubOrganization(passkey: Passkey) async throws -> CreateSubOrganizationResponse {
        let url = baseURL.appendingPathComponent("v1/wallets")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(Secrets.FIREBASE_APP_CHECK_TOKEN, forHTTPHeaderField: "X-Firebase-AppCheck")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody: [String: Any] = [
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
                  httpResponse.statusCode == 200 else {
                throw APIError.authenticationFailed
            }

            let result = try JSONDecoder().decode(CreateSubOrganizationResponse.self, from: data)
            Logger.info("createSubOrganization response: \(response)")
            return result
        } catch {
            throw APIError.serverError(error)
        }
    }

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
