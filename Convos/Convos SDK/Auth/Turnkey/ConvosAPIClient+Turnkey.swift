import Foundation

extension ConvosAPIClient {
    func createSubOrganization(
        ephemeralPublicKey: String,
        passkey: Passkey
    ) async throws -> CreateSubOrganizationResponse {
        let url = baseURL.appendingPathComponent("v1/wallets")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(Secrets.FIREBASE_APP_CHECK_TOKEN, forHTTPHeaderField: "X-Firebase-AppCheck")
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

            let result = try JSONDecoder().decode(CreateSubOrganizationResponse.self, from: data)
            return result
        } catch {
            throw APIError.serverError(error)
        }
    }
}
